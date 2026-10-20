# Raumsteuerung Sitzungszimmer 5 - Teams-Meeting vom Tablet bedienen (Mikro, Bild, Verlassen)
#
# Ohne Teams-API: liest und drueckt die Buttons im Teams-Meetingfenster per Windows UI Automation
# (dieselbe Schnittstelle, die Bildschirmleser nutzen). Die Buttons haben feste Kennungen
# (microphone-button, video-button, hangup-button), unabhaengig von der Sprache.
#   - Zustand -> Companion-Variablen r5_t_in (im Meeting), r5_t_mute (stumm), r5_t_video (Bild an)
#   - Befehl  <- Companion-Variable r5_tcmd (mute | video | leave | join, vom Tablet: mic_on/mic_off/video_on/
#               video_off = Zielzustand), wird nach dem Ausfuehren geleert
#   - join: oeffnet den festen Meeting-Link des Raums (teams-link.txt), Kamera + Mikro an, "Jetzt teilnehmen",
#           das Meetingfenster bleibt offen (eigener Monitor am Sprecherplatz). Fortschritt in r5_t_status
#           ("start" waehrend des Beitritts, "fehler: ..." wenn es nicht klappt, sonst leer).
# Modus "teilen" (Standard, siehe unten): Teams bekommt das OBS-Bild nicht ueber die Virtuelle Kamera, sondern
#   als geteilter Bildschirm (OBS-Vollbild-Projektor auf einem virtuellen Bildschirm). join teilt danach automatisch,
#   video_on/video_off = Teilen an/aus, leave beendet vorher das Teilen.
# Ausserdem OBS-Waechter: startet OBS beim Anmelden und nach einem Absturz (alle 30 s geprueft).
# Muss in der Sitzung des angemeldeten Benutzers laufen (nicht als SYSTEM) - Aufgabe "bei Anmeldung".
#
# Aufruf:
#   .\teams-steuerung.ps1            dauerhaft (startet per Aufgabenplanung)
#   .\teams-steuerung.ps1 -Status    einmal Zustand anzeigen (Test)
#   .\teams-steuerung.ps1 -Befehl mute   einmal Mikro umschalten (Test, ohne Companion)
param(
  [switch]$Status,
  [ValidateSet('', 'mute', 'video', 'leave', 'join', 'share_on', 'share_off')][string]$Befehl = '',
  [string]$Companion = '',
  [string]$Log = (Join-Path $PSScriptRoot 'teams-steuerung.log')
)
$ErrorActionPreference = 'Stop'
# Echte Pixel auf allen Bildschirmen (Laptop 125 %, Monitore 100 %): sonst passen Bildschirm-, Fenster- und
# Maus-Koordinaten nicht zusammen und die Maus-Sperre fuer den Teilen-Bildschirm sitzt an der falschen Stelle
Add-Type -Namespace Dpi -Name Api -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);'
[void][Dpi.Api]::SetProcessDpiAwarenessContext([IntPtr](-4))   # PER_MONITOR_AWARE_V2
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Fenster {
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DISPLAY_DEVICE {
    public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString; public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
  // Monitorname + Hardware-ID zu \\.\DISPLAYn (z. B. "Generic Monitor (VDD by MTT)  MONITOR\MTT1337\...")
  public static string Monitor(string dev) {
    var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
    return EnumDisplayDevices(dev, 0, ref dd, 0) ? dd.DeviceString + "  " + dd.DeviceID : "";
  }
}
'@
# Schutz des Teilen-Bildschirms: Maus bleibt auf den echten Bildschirmen, versehentlich dorthin geschobene Fenster
# kommen zurueck, der OBS-Projektor liegt immer oben -> die Teilnehmer sehen nur das OBS-Bild
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Schutz {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  delegate bool CB(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(CB cb, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool ClipCursor(ref RECT r);
  [DllImport("user32.dll")] static extern bool GetClipCursor(out RECT r);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  static readonly string[] Shell = { "Shell_SecondaryTrayWnd", "Shell_TrayWnd", "Progman", "WorkerW" };
  // Maus auf "frei" begrenzen (Windows hebt die Begrenzung bei manchen Aktionen auf -> regelmaessig erneuern)
  // Rechtecke als x, y, Breite, Hoehe (ohne System.Drawing, laeuft in Windows PowerShell und PowerShell 7)
  public static void Maus(int x, int y, int w, int h) {
    RECT c; GetClipCursor(out c);
    if (c.L != x || c.T != y || c.R != x + w || c.B != y + h) { RECT r = new RECT { L = x, T = y, R = x + w, B = y + h }; ClipCursor(ref r); }
  }
  // Fenster mit Mittelpunkt auf dem Teilen-Bildschirm zurueck nach "frei" schieben; Projektor nach oben
  public static List<string> Fenster(int tx, int ty, int tw, int th, int fx, int fy, int fw, int fh, IntPtr projektor, uint[] erlaubt) {
    var weg = new List<string>();
    EnumWindows((h, l) => {
      if (h == projektor || !IsWindowVisible(h) || IsIconic(h)) return true;
      int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
      uint pid; GetWindowThreadProcessId(h, out pid); if (Array.IndexOf(erlaubt, pid) >= 0) return true;
      var cls = new StringBuilder(256); GetClassName(h, cls, 256); if (Array.IndexOf(Shell, cls.ToString()) >= 0) return true;
      RECT r; GetWindowRect(h, out r);
      int mx = (r.L + r.R) / 2, my = (r.T + r.B) / 2;
      if (mx < tx || mx >= tx + tw || my < ty || my >= ty + th) return true;
      bool max = IsZoomed(h); if (max) ShowWindow(h, 9);   // 9 = SW_RESTORE
      GetWindowRect(h, out r);
      int w = Math.Min(r.R - r.L, fw), hh = Math.Min(r.B - r.T, fh);
      SetWindowPos(h, IntPtr.Zero, fx + (fw - w) / 2, fy + (fh - hh) / 2, w, hh, 0x0014);  // NOZORDER|NOACTIVATE
      if (max) ShowWindow(h, 3);                           // 3 = SW_MAXIMIZE (jetzt auf dem echten Bildschirm)
      weg.Add(cls.ToString());
      return true;
    }, IntPtr.Zero);
    if (projektor != IntPtr.Zero) SetWindowPos(projektor, new IntPtr(-1), 0, 0, 0, 0, 0x0013);   // TOPMOST, NOMOVE|NOSIZE|NOACTIVATE
    return weg;
  }
}
'@
Add-Type -AssemblyName System.Windows.Forms

$cfg = $null
try { $cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'mikro-automatik.json') | ConvertFrom-Json } catch { }
if (-not $Companion) { $Companion = if ($cfg -and $cfg.companion) { $cfg.companion } else { 'http://127.0.0.1:8000' } }
# Wie Teams das Bild bekommt (mikro-automatik.json, optional):
#   teamsBild "teilen" (Standard): zwei Kanaele wie bei Teams Rooms. Inhalt: OBS-Szene "Inhalt" (nur Praesentation)
#             als Vollbild-Projektor auf einem eigenen (virtuellen) Bildschirm, Teams teilt ihn -> scharf und gross.
#             Personen: Virtuelle Kamera (OBS-Programm, Szenen Nur Redner / Diskussion / Pausenbild) -> fluessig.
#             "Bild an/aus" auf dem Tablet = Teilen + Kamera an/aus.
#   teamsBild "kamera": wie bisher ueber die Virtuelle Kamera von OBS.
#   teilenTon true/false: "Sound einschliessen" (Ton von Videos in der Praesentation) - Standard an.
#   teilenBildschirm: Teil des Monitornamens des Teilen-Bildschirms, Standard "MTT" (Virtual Display Driver);
#             nicht gefunden -> der letzte Bildschirm, der nicht der Hauptbildschirm ist.
$Teilen = -not ($cfg -and $cfg.teamsBild -eq 'kamera')
$TeilenTon = -not ($cfg -and $cfg.teilenTon -eq $false)
$TeilenName = if ($cfg -and $cfg.teilenBildschirm) { $cfg.teilenBildschirm } else { 'MTT' }
$IDS = @{ mute = 'microphone-button'; video = 'video-button'; leave = 'hangup-button' }
# Beschriftung des Buttons, wenn der Zustand AUS ist (Mikro stumm / Kamera aus): "Mikrofon wieder aktivieren",
# "Kamera aktivieren"; englisch "Unmute", "Turn camera on". An = "... stummschalten" / "Kamera ausschalten".
$AUS = '(?i)aktivieren|einschalten|aufheben|unmute|turn camera on|start video'

function Write-Log([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
  Write-Host $line
  try {
    if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 1MB) { Move-Item $Log ($Log + '.alt') -Force }
    Add-Content -Path $Log -Value $line -Encoding UTF8
  } catch { }
}

# ---------- Companion (HTTP-API) ----------
function Invoke-Companion([string]$method, [string]$path) {
  $req = [System.Net.HttpWebRequest]::Create($Companion + $path)
  $req.Method = $method; $req.Timeout = 1500; $req.ReadWriteTimeout = 1500
  if ($method -eq 'POST') { $req.ContentLength = 0 }
  $res = $req.GetResponse()
  try { $sr = New-Object System.IO.StreamReader($res.GetResponseStream()); return $sr.ReadToEnd() } finally { $res.Close() }
}
function Get-Var([string]$name) { try { return (Invoke-Companion 'GET' "/api/custom-variable/$name/value").Trim() } catch { return $null } }
function Set-Var([string]$name, [string]$value) {
  try { [void](Invoke-Companion 'POST' ("/api/custom-variable/$name/value?value=" + [Uri]::EscapeDataString($value))); return $true } catch { return $false }
}

# ---------- Teams (UI Automation) ----------
$script:win = $null
function Cond([string]$id) { New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $id) }
$cHang = Cond 'hangup-button'
function Find-Meeting {
  # gemerktes Fenster noch gueltig und noch im Meeting?
  if ($script:win) {
    # minimiert -> neu suchen (vielleicht gibt es jetzt die Kompaktleiste)
    try { if (-not [Fenster]::IsIconic([IntPtr]$script:win.Current.NativeWindowHandle) -and $script:win.FindFirst($Scope::Descendants, $cHang)) { return $script:win } } catch { }
    $script:win = $null
  }
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  if (-not $ids.Count) { return $null }
  # Ist das Meetingfenster minimiert, zeigt Teams eine kleine Kompaktleiste (eigenes Fenster) - die bevorzugen,
  # dann muss das grosse Fenster nicht aufgehen.
  $treffer = @()
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($ids -contains $w.Current.ProcessId -and $w.FindFirst($Scope::Descendants, $cHang)) { $treffer += $w } } catch { }
  }
  if (-not $treffer.Count) { return $null }
  $offen = @($treffer | Where-Object { -not [Fenster]::IsIconic([IntPtr]$_.Current.NativeWindowHandle) })
  $script:win = if ($offen.Count) { $offen | Sort-Object { $_.Current.BoundingRectangle.Width } | Select-Object -First 1 } else { $treffer[0] }
  return $script:win
}
function Get-TeamsState {
  $w = Find-Meeting
  # Waehrend das Teilen-Menue ("Inhalt freigeben") offen ist, verdeckt es die Meeting-Leiste -> kein hangup-button.
  # Dann ist der Raum trotzdem im Meeting; Zustand als unbekannt melden (Hauptschleife behaelt den letzten).
  if (-not $w) { return @{ In = $false; Mute = $false; Video = $false; Share = $false; Menue = [bool]((Find-ShareTray) -or (Find-LeaveDialog $null)) } }
  $mic = $w.FindFirst($Scope::Descendants, (Cond $IDS.mute))
  $cam = $w.FindFirst($Scope::Descendants, (Cond $IDS.video))
  $shr = $w.FindFirst($Scope::Descendants, (Cond 'share-button'))
  $share = [bool]($shr -and $shr.Current.Name -match $TEILT)
  return @{
    In    = $true
    Mute  = [bool]($mic -and $mic.Current.Name -match $AUS)
    # Modus "teilen": "Bild an" heisst, Teams teilt den OBS-Bildschirm
    Video = if ($Teilen) { $share } else { [bool]($cam -and $cam.Current.Name -notmatch $AUS) }
    Share = $share
    Menue = $false
  }
}

function Find-LeaveDialog($w) {
  # Rueckfrage "Bleiben" / "Verlassen" (verdeckt die Meeting-Leiste, wie das Teilen-Menue)
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  $c = New-Object System.Windows.Automation.OrCondition((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Bleiben')),
                                                       (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Stay')))
  foreach ($x in $(if ($w) { @($w) } else { $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition) })) {
    try { if ($ids -contains $x.Current.ProcessId -and $x.FindFirst($Scope::Descendants, $c)) { return $x } } catch { }
  }
  return $null
}
function Confirm-Leave($w) {
  for ($i = 0; $i -lt 6; $i++) {
    $d = Find-LeaveDialog $w
    if ($d) {
      $cB = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
      $ok = @($d.FindAll($Scope::Descendants, $cB)) | Where-Object { $_.Current.Name -match '(?i)^(verlassen|leave)$' -and $_.Current.AutomationId -ne 'hangup-button' } | Select-Object -First 1
      if ($ok) { $ok.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-Log 'Verlassen: Rueckfrage bestaetigt'; return }
    }
    Start-Sleep -Milliseconds 300
  }
}

# ---------- Bildschirm teilen (Modus "teilen") ----------
# share-button heisst "Teilen", waehrend des Teilens "Teilen beenden" (engl. "Share" / "Stop sharing")
$TEILT = '(?i)beenden|stop'
function Find-ShareTray {
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  $c = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Bildschirm auswählen')
  $c2 = New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Select screen')
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      $l = $w.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.OrCondition($c, $c2)))
      if ($l) { return @{ Win = $w; List = $l } }
    } catch { }
  }
  return $null
}
function Get-ShareScreen {
  # Bildschirm fuer das Teilen: Monitorname enthaelt $TeilenName (Virtual Display Driver: "VDD by MTT"),
  # sonst der letzte Bildschirm, der nicht der Hauptbildschirm ist
  $alle = [System.Windows.Forms.Screen]::AllScreens
  for ($i = 0; $i -lt $alle.Count; $i++) {
    if ([Fenster]::Monitor($alle[$i].DeviceName) -like "*$TeilenName*") { return @{ Index = $i; Bounds = $alle[$i].Bounds } }
  }
  for ($i = $alle.Count - 1; $i -ge 0; $i--) { if (-not $alle[$i].Primary) { return @{ Index = $i; Bounds = $alle[$i].Bounds } } }
  return $null
}
function In-Bounds($rect, $b) {
  $x = $rect.X + $rect.Width / 2; $y = $rect.Y + $rect.Height / 2
  return ($x -ge $b.X -and $x -lt $b.X + $b.Width -and $y -ge $b.Y -and $y -lt $b.Y + $b.Height)
}
function Find-Projector($b) {
  $obs = @(Get-Process obs64 -ErrorAction SilentlyContinue).Id
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($obs -contains $w.Current.ProcessId -and $w.Current.Name -match '(?i)^(projektor|projector)' -and $w.Current.Name -match $PROJ -and (In-Bounds $w.Current.BoundingRectangle $b)) { return $w } } catch { }
  }
  return $null
}
$PROJ = 'Inhalt'   # OBS-Szene, die geteilt wird (Projektor-Titel z. B. "Projektor (Quelle) - Inhalt")
function Close-OtherProjectors($b) {
  # alte Projektoren (z. B. "Programm") auf dem Teilen-Bildschirm schliessen
  $obs = @(Get-Process obs64 -ErrorAction SilentlyContinue).Id
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($obs -contains $w.Current.ProcessId -and $w.Current.Name -match '(?i)^(projektor|projector)' -and $w.Current.Name -notmatch $PROJ -and (In-Bounds $w.Current.BoundingRectangle $b)) {
        $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Write-Log "Teilen: alten Projektor '$($w.Current.Name)' geschlossen"
      }
    } catch { }
  }
}
function Protect-ShareScreen {
  # nur wenn es einen Teilen-Bildschirm gibt; "frei" = die uebrigen Bildschirme (bzw. der Hauptbildschirm)
  $s = Get-ShareScreen; if (-not $s) { return }
  $frei = [System.Drawing.Rectangle]::Empty
  foreach ($x in [System.Windows.Forms.Screen]::AllScreens) {
    if ($x.Bounds -eq $s.Bounds) { continue }
    $frei = if ($frei.IsEmpty) { $x.Bounds } else { [System.Drawing.Rectangle]::Union($frei, $x.Bounds) }
  }
  if ($frei.IsEmpty -or $frei.IntersectsWith($s.Bounds)) {
    # Teilen-Bildschirm liegt zwischen zwei echten Monitoren -> Maus nur auf dem Hauptbildschirm moeglich
    if (-not $script:warnLage) { Write-Log 'Teilen-Bildschirm liegt zwischen den Monitoren - in den Anzeigeeinstellungen ganz nach rechts schieben (sonst kommt die Maus nicht auf die anderen Monitore)'; $script:warnLage = $true }
    $frei = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  } else { $script:warnLage = $false }
  [Schutz]::Maus($frei.X, $frei.Y, $frei.Width, $frei.Height)
  if (([DateTime]::Now - $script:lastSchutz).TotalMilliseconds -lt 1000) { return }
  $script:lastSchutz = [DateTime]::Now
  # Projektor-Suche per UI Automation ist teuer -> nur alle 5 s, dazwischen das gemerkte Fenster
  if (([DateTime]::Now - $script:lastProj).TotalSeconds -ge 5) {
    $script:lastProj = [DateTime]::Now
    Close-OtherProjectors $s.Bounds
    $p = Find-Projector $s.Bounds
    $script:projHwnd = if ($p) { [IntPtr]$p.Current.NativeWindowHandle } else { [IntPtr]::Zero }
  }
  $h = $script:projHwnd
  # Teams-Rahmen/-Leiste beim Teilen; OBS-Projektoren nie verschieben (Vollbild auf dem Hauptbildschirm wuerde ihn verdecken)
  $erlaubt = [uint32[]]@(Get-Process ms-teams, obs64 -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
  foreach ($k in [Schutz]::Fenster($s.Bounds.X, $s.Bounds.Y, $s.Bounds.Width, $s.Bounds.Height, $frei.X, $frei.Y, $frei.Width, $frei.Height, $h, $erlaubt)) { Write-Log "Teilen-Bildschirm: Fenster ($k) zurueck auf den Hauptbildschirm" }
}
$script:lastSchutz = [DateTime]::MinValue; $script:lastProj = [DateTime]::MinValue; $script:projHwnd = [IntPtr]::Zero
function Ensure-Projector {
  # OBS-Programm als Vollbild-Projektor auf dem Teilen-Bildschirm (Companion-Button 1/3/9, Monitor-Nr. in r5_proj_mon;
  # OBS zaehlt die Bildschirme in derselben Reihenfolge wie Windows)
  $s = Get-ShareScreen
  if (-not $s) { Write-Log 'Teilen: kein zweiter Bildschirm (Virtual Display Driver / HDMI-Dummy) gefunden'; return $null }
  if (Find-Projector $s.Bounds) { return $s }
  Close-OtherProjectors $s.Bounds
  [void](Set-Var 'r5_proj_mon' ([string]$s.Index))
  try { [void](Invoke-Companion 'POST' '/api/location/1/3/9/press') } catch { }
  for ($i = 0; $i -lt 10 -and -not (Find-Projector $s.Bounds); $i++) { Start-Sleep -Milliseconds 500 }
  if (Find-Projector $s.Bounds) { Write-Log "Teilen: OBS-Projektor auf Bildschirm $($s.Index) geoeffnet"; return $s }
  Write-Log 'Teilen: OBS-Projektor laesst sich nicht oeffnen (laeuft OBS? Companion-Button 1/3/9?)'; return $null
}
function Find-ShareBar {
  # Teams zeigt beim Teilen die "Freigabesteuerungsleiste" oben auf dem geteilten Bildschirm
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($ids -contains $w.Current.ProcessId -and $w.Current.Name -match '(?i)^(freigabesteuerungsleiste|sharing control bar)') { return $w } } catch { }
  }
  return $null
}
function Set-PeopleScene {
  # Beim Teilen kommt die Praesentation getrennt -> die Kamera soll Personen zeigen, nicht noch einmal die Folien
  for ($i = 0; $i -lt 4; $i++) {   # langsamer PC: Companion antwortet evtl. erst beim zweiten Versuch
    try {
      $sc = (Invoke-Companion 'GET' '/api/variable/obs/scene_active/value').Trim()
      if ($sc -notin 'Alles im Blick', 'Folien Groß', 'Folien groß') { return }
      [void](Invoke-Companion 'POST' '/api/location/1/1/4/press'); Write-Log "Teilen: Kamera-Szene '$sc' -> 'Nur Redner'"; return
    } catch { Start-Sleep -Milliseconds 700 }
  }
  Write-Log 'Teilen: Kamera-Szene nicht umgeschaltet (Companion antwortet nicht)'
}
function Set-Camera([bool]$an) {
  $s = Get-TeamsState
  $cam = $null; $w = Find-Meeting; if ($w) { $cam = $w.FindFirst($Scope::Descendants, (Cond $IDS.video)) }
  if ($cam -and (($cam.Current.Name -notmatch $AUS) -ne $an)) { [void](Invoke-Teams 'video') }
}
function Stop-Share {
  $w = Find-Meeting; if (-not $w) { return $false }
  $b = $w.FindFirst($Scope::Descendants, (Cond 'share-button'))
  if (-not $b -or $b.Current.Name -notmatch $TEILT) { return $true }
  $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 300; $b = $w.FindFirst($Scope::Descendants, (Cond 'share-button')); if ($b -and $b.Current.Name -notmatch $TEILT) { break } }
  Write-Log 'Teilen beendet'; return $true
}
function Start-Share {
  $w = Find-Meeting
  if (-not $w) { Write-Log 'Teilen: kein Teams-Meeting offen'; return $false }
  $s = Ensure-Projector; if (-not $s) { return $false }
  $b = $w.FindFirst($Scope::Descendants, (Cond 'share-button'))
  if (-not $b) { Write-Log 'Teilen: Button share-button nicht gefunden'; return $false }
  if ($b.Current.Name -match $TEILT) {
    $bar = Find-ShareBar
    if (-not $bar -or (In-Bounds $bar.Current.BoundingRectangle $s.Bounds)) { return $true }   # teilt schon den richtigen
    Write-Log 'Teilen: falscher Bildschirm geteilt -> neu'; [void](Stop-Share); Start-Sleep -Milliseconds 800
  }
  $h = [IntPtr]$w.Current.NativeWindowHandle; $vorne = [Fenster]::GetForegroundWindow()
  if ([Fenster]::IsIconic($h)) { [void][Fenster]::ShowWindow($h, 4); Start-Sleep -Milliseconds 500 }
  # Bildschirme im Menue heissen alle gleich ("Generic PnP Monitor"). Teams listet sie in der Windows-Reihenfolge ->
  # zuerst den Eintrag mit derselben Nummer, dann die uebrigen; an der Lage der Teams-Leiste pruefen, ob es stimmt
  $probiert = @()
  for ($versuch = 0; $versuch -lt 5; $versuch++) {
    $t = Find-ShareTray
    if (-not $t) {
      try { $w.FindFirst($Scope::Descendants, (Cond 'share-button')).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { }
      for ($i = 0; $i -lt 16 -and -not ($t = Find-ShareTray); $i++) { Start-Sleep -Milliseconds 250 }
      if (-not $t) { Write-Log 'Teilen: Teilen-Menue geht nicht auf'; return $false }
    }
    Start-Sleep -Milliseconds 400
    # nur der Inhalt (kein Sprecher-Ausschnitt darueber), Ton nach Einstellung
    try {
      $ro = $t.Win.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Nur Inhalt')))
      if ($ro) { $sp = $ro.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern); if (-not $sp.Current.IsSelected) { $sp.Select() } }
      $cB = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
      $ton = @($t.Win.FindAll($Scope::Descendants, $cB)) | Where-Object { $_.Current.Name -match '(?i)sound|ton einschl|include.*(sound|audio)' } | Select-Object -First 1
      if ($ton) {
        $tp = $ton.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        if (($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) -ne $TeilenTon) { $tp.Toggle() }
      }
    } catch { Write-Log ('Teilen: Optionen nicht gesetzt (' + $_.Exception.Message + ')') }
    $items = @($t.List.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition))
    $reihe = @($s.Index) + @(($items.Count - 1)..0 | Where-Object { $_ -ne $s.Index })
    $nr = $reihe | Where-Object { $_ -lt $items.Count -and $probiert -notcontains $_ } | Select-Object -First 1
    if ($null -eq $nr) { Write-Log 'Teilen: Teilen-Bildschirm nicht in der Teams-Liste'; return $false }
    $probiert += $nr
    $items[$nr].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $bar = $null; for ($i = 0; $i -lt 20 -and -not ($bar = Find-ShareBar); $i++) { Start-Sleep -Milliseconds 300 }
    if ($bar -and (In-Bounds $bar.Current.BoundingRectangle $s.Bounds)) {
      Write-Log "Teilen: Bildschirm $($s.Index) wird geteilt (Eintrag $($nr + 1) von $($items.Count), Ton $(if ($TeilenTon) { 'an' } else { 'aus' }))"
      if ($vorne -ne [IntPtr]::Zero -and [Fenster]::IsWindowVisible($vorne) -and -not [Fenster]::IsIconic($vorne)) { [void][Fenster]::SetForegroundWindow($vorne) }
      return $true
    }
    Write-Log "Teilen: Eintrag $($nr + 1) ist nicht der Teilen-Bildschirm -> naechster"
    [void](Stop-Share); Start-Sleep -Milliseconds 800
  }
  return $false
}
function Invoke-Teams([string]$cmd) {
  # Beim Teilen fragt Teams vor dem Verlassen nach ("Sie geben gerade frei ...") -> erst das Teilen beenden
  if ($cmd -eq 'leave' -and (Get-TeamsState).Share) { [void](Stop-Share); Start-Sleep -Milliseconds 500 }
  $w = Find-Meeting
  if (-not $w) { Write-Log "Befehl ${cmd}: kein Teams-Meeting offen"; return $false }
  $b = $w.FindFirst($Scope::Descendants, (Cond $IDS[$cmd]))
  if (-not $b) { Write-Log "Befehl ${cmd}: Button $($IDS[$cmd]) nicht gefunden"; return $false }
  # Teams holt sein Fenster beim Druecken nach vorn. Auf dem Raum-PC laeuft evtl. eine Praesentation
  # auf den Displays -> danach den vorherigen Zustand wiederherstellen.
  $h = [IntPtr]$w.Current.NativeWindowHandle
  $vorne = [Fenster]::GetForegroundWindow(); $warMin = [Fenster]::IsIconic($h)
  # Ein minimiertes Teams-Fenster (WebView) verarbeitet Klicks erst Sekunden spaeter -> ohne Aktivieren
  # wiederherstellen (4 = SW_SHOWNOACTIVATE), dann druecken. Das Fenster bleibt danach offen
  # (Teams laeuft auf dem eigenen Monitor am Sprecherplatz).
  if ($warMin) { [void][Fenster]::ShowWindow($h, 4); $warMin = $false; Start-Sleep -Milliseconds 500; $b = $w.FindFirst($Scope::Descendants, (Cond $IDS[$cmd])) }
  $name = $b.Current.Name
  try { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
  catch {
    # "Verlassen" ist manchmal ein Menue-Knopf mit Rueckfrage -> aufklappen und dort "Verlassen" bestaetigen
    $b.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep -Milliseconds 800
  }
  if ($cmd -eq 'leave') { Confirm-Leave $w }
  # warten, bis Teams umgeschaltet hat (Beschriftung wechselt), damit der gemeldete Zustand stimmt
  if ($cmd -ne 'leave') {
    $ende = [DateTime]::Now.AddSeconds(3)
    do { Start-Sleep -Milliseconds 150; $neu = try { $w.FindFirst($Scope::Descendants, (Cond $IDS[$cmd])).Current.Name } catch { $name } } while ($neu -eq $name -and [DateTime]::Now -lt $ende)
    if ($neu -eq $name) { Write-Log "Befehl ${cmd}: Teams hat nach 3 s noch nicht umgeschaltet" }
  } else { Start-Sleep -Milliseconds 400 }
  if ($warMin -and -not [Fenster]::IsIconic($h)) { [void][Fenster]::ShowWindow($h, 6) }      # 6 = SW_MINIMIZE
  # nur ein sichtbares, nicht minimiertes Fenster zurueckholen (sonst taucht z. B. das versteckte Companion-Fenster auf)
  if ($vorne -ne [IntPtr]::Zero -and $vorne -ne $h -and [Fenster]::IsWindowVisible($vorne) -and -not [Fenster]::IsIconic($vorne) -and
      [Fenster]::GetForegroundWindow() -ne $vorne) { [void][Fenster]::SetForegroundWindow($vorne) }
  Write-Log ("Befehl {0}: '{1}' gedrueckt" -f $cmd, $name)
  if ($cmd -eq 'leave') {
    $script:win = $null
    # Abschlussfenster erscheint nach 1-3 s
    for ($i = 0; $i -lt 8; $i++) { Start-Sleep -Milliseconds 700; Close-AfterMeeting }
  }
  return $true
}

# ---------- OBS-Waechter: OBS muss immer laufen (sonst hat Teams kein Bild) ----------
# Startet OBS beim Anmelden und nach einem Absturz neu: im Infobereich, ohne "Abgesicherter Modus?"-Frage.
# Ist der Raum gerade an (r5_room = 1), gleich mit Virtual Camera.
$OBS = 'C:\Program Files\obs-studio\bin\64bit\obs64.exe'
function Ensure-Obs {
  if (Get-Process obs64 -ErrorAction SilentlyContinue) { return }
  if (-not (Test-Path $OBS)) { if (-not $script:obsFehlt) { Write-Log "OBS nicht gefunden: $OBS"; $script:obsFehlt = $true }; return }
  $arg = '--minimize-to-tray --disable-shutdown-check'
  if ((Get-Var 'r5_room') -eq '1') { $arg += ' --startvirtualcam' }
  Start-Process -FilePath $OBS -ArgumentList $arg -WorkingDirectory (Split-Path $OBS)   # OBS braucht sein Programmverzeichnis
  Write-Log "OBS gestartet ($arg)"
}

# ---------- Nach dem Meeting: Fenster "Bleiben Sie nach Ihrer Besprechung in Verbindung" schliessen ----------
# Teams zeigt es nach jedem Verlassen; auf dem Raum-PC stuende es sonst auf den Displays.
# Erkennung ueber den Button "Erneut dem Anruf beitreten" (engl. "Rejoin"), dann "Verwerfen" bzw. Fenster schliessen.
function Close-AfterMeeting {
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  if (-not $ids.Count) { return }
  $cBtn = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      $btns = @($w.FindAll($Scope::Descendants, $cBtn))
      if (-not ($btns | Where-Object { $_.Current.Name -match '(?i)erneut.*beitreten|rejoin' })) { continue }
      if ($btns | Where-Object { $_.Current.AutomationId -eq 'hangup-button' }) { continue }   # noch im Meeting
      $weg = $btns | Where-Object { $_.Current.Name -match '(?i)^(verwerfen|dismiss)$' } | Select-Object -First 1
      if ($weg) { $weg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
      else { $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }
      Write-Log 'Nach dem Meeting: Abschlussfenster geschlossen'
    } catch { }
  }
}

# ---------- Meeting des Raums beitreten ----------
$cJoin = Cond 'prejoin-join-button'
function Find-Prejoin {
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($ids -contains $w.Current.ProcessId -and $w.FindFirst($Scope::Descendants, $cJoin)) { return $w } } catch { }
  }
  return $null
}
function Set-Switch($w, [string]$muster, [bool]$an = $true) {
  # Kamera-/Mikro-Schalter im Beitrittsfenster ein-/ausschalten (Kennungen wechseln, daher per Name + TogglePattern)
  $cBtn = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  foreach ($b in $w.FindAll($Scope::Descendants, $cBtn)) {
    if ($b.Current.Name -notmatch $muster) { continue }
    try { $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern) } catch { continue }
    if (($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) -ne $an) { $tp.Toggle(); Write-Log ("Beitritt: '$($b.Current.Name)' " + $(if ($an) { 'eingeschaltet' } else { 'ausgeschaltet' })) }
    return
  }
}
function Join-Teams {
  if (Find-Meeting) { Write-Log 'Beitritt: Raum ist schon im Meeting'; [void](Set-Var 'r5_t_status' ''); return $true }
  $f = Join-Path $PSScriptRoot 'teams-link.txt'
  $link = if (Test-Path $f) { (Get-Content $f -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -First 1) } else { $null }
  if (-not $link) { Write-Log 'Beitritt: teams-link.txt fehlt oder ist leer'; [void](Set-Var 'r5_t_status' 'fehler: kein Meeting-Link'); return $false }
  # https-Link -> msteams:-Link, damit die Teams-App direkt den Beitrittsbildschirm oeffnet (kein Browser)
  $uri = $link.Trim() -replace '^https?://teams\.(microsoft|live)\.com', 'msteams:'
  [void](Set-Var 'r5_t_status' 'start')
  Write-Log 'Beitritt: oeffne Meeting-Link'
  Start-Process $uri
  # Beitrittsbildschirm abwarten. War schon einer offen, baut Teams ihn neu auf -> bei "Element nicht verfuegbar"
  # kurz warten und neu suchen (bis 45 s).
  $ende = [DateTime]::Now.AddSeconds(45); $gedrueckt = $false
  Start-Sleep -Seconds 3
  while (-not $gedrueckt -and [DateTime]::Now -lt $ende) {
    if (Find-Meeting) { break }
    $pre = Find-Prejoin
    if ($pre) {
      try {
        Set-Switch $pre '(?i)^kamera|camera'   # Personen ueber die Virtuelle Kamera (auch im Modus teilen)
        Set-Switch $pre '(?i)^mikrofon|^mute|microphone'
        $pre.FindFirst($Scope::Descendants, $cJoin).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $gedrueckt = $true
        Write-Log 'Beitritt: "Jetzt teilnehmen" gedrueckt'
      } catch { Write-Log ('Beitritt: Beitrittsbildschirm noch nicht bereit (' + $_.Exception.Message + ')') }
    }
    if (-not $gedrueckt) { Start-Sleep -Milliseconds 1000 }
  }
  $ende = [DateTime]::Now.AddSeconds(40); $w = $null
  while (-not $w -and [DateTime]::Now -lt $ende) { Start-Sleep -Milliseconds 700; $w = Find-Meeting }
  if (-not $w) { Write-Log 'Beitritt fehlgeschlagen (kein Meetingfenster)'; [void](Set-Var 'r5_t_status' 'fehler: Teams reagiert nicht'); return $false }
  Start-Sleep -Seconds 2
  $script:win = $null
  Write-Log 'Beitritt: im Meeting'
  if ($Teilen -and -not (Start-Share)) { [void](Set-Var 'r5_t_status' 'fehler: Bild teilen'); return $true }
  if ($Teilen) { Set-PeopleScene }
  [void](Set-Var 'r5_t_status' '')
  return $true
}

# ---------- Testaufrufe ----------
if ($Status) { $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}  Teilt: {3}  Menue offen: {4}  Modus: {5}' -f $s.In, $s.Mute, $s.Video, $s.Share, $s.Menue, $(if ($Teilen) { 'teilen' } else { 'kamera' }); exit 0 }
if ($Befehl -in 'share_on', 'share_off') { [void]$(if ($Befehl -eq 'share_on') { Start-Share } else { Stop-Share }); $s = Get-TeamsState; 'Im Meeting: {0}  Teilt: {1}' -f $s.In, $s.Share; exit 0 }
if ($Befehl -eq 'join') { [void](Join-Teams); $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}' -f $s.In, $s.Mute, $s.Video; exit 0 }
if ($Befehl) { [void](Invoke-Teams $Befehl); Start-Sleep -Milliseconds 800; $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}' -f $s.In, $s.Mute, $s.Video; exit 0 }

# ---------- Hauptschleife ----------
Write-Log ('Start Teams-Steuerung, Companion ' + $Companion + ', Benutzer ' + $env:USERNAME)
$last = @{}; $lastPush = [DateTime]::MinValue; $nextState = [DateTime]::MinValue; $companionOk = $true; $script:lastClose = [DateTime]::MinValue; $script:lastObs = [DateTime]::MinValue
while ($true) {
  try {
    # Befehl vom Tablet / Stream Deck
    $cmd = Get-Var 'r5_tcmd'
    if ($null -eq $cmd) { if ($companionOk) { Write-Log 'Companion nicht erreichbar'; $companionOk = $false } }
    else {
      if (-not $companionOk) { Write-Log 'Companion wieder erreichbar'; $companionOk = $true; $last = @{} }
      if ($cmd) {
        [void](Set-Var 'r5_tcmd' '')          # zuerst leeren: ein Tippen = ein Druck
        if ($cmd -eq 'join') { [void](Join-Teams); $nextState = [DateTime]::MinValue }
        elseif ($cmd -match '^(mic|video)_(on|off)$') {
          # Zielzustand statt Umschalten (vom Tablet): nur druecken, wenn Teams anders steht -> verlorene oder
          # doppelte Befehle koennen den Zustand nicht verdrehen
          $was = $Matches[1]; $soll = $Matches[2] -eq 'on'
          $s = Get-TeamsState
          $ist = if ($was -eq 'mic') { -not $s.Mute } else { $s.Video }
          if (-not $s.In) { Write-Log "Befehl ${cmd}: kein Teams-Meeting offen" }
          elseif ($was -eq 'video' -and $Teilen) {
            # Bild an/aus = Praesentation (Teilen) und Personen (Kamera) zusammen
            if ($soll) { if (Start-Share) { [void](Set-Var 'r5_t_status' ''); Set-PeopleScene } else { [void](Set-Var 'r5_t_status' 'fehler: Bild teilen') }; Set-Camera $true }
            else { [void](Stop-Share); Set-Camera $false }
          }
          elseif ($ist -ne $soll) { [void](Invoke-Teams $(if ($was -eq 'mic') { 'mute' } else { 'video' })) }
          else { Write-Log "Befehl ${cmd}: Teams steht schon so" }
          $nextState = [DateTime]::MinValue
        }
        elseif ($cmd -eq 'video' -and $Teilen) { $s = Get-TeamsState; if ($s.Share) { [void](Stop-Share); Set-Camera $false } else { [void](Start-Share); Set-Camera $true }; $nextState = [DateTime]::MinValue }
        elseif ($cmd -in 'share_on', 'share_off') { if ($cmd -eq 'share_on') { [void](Start-Share) } else { [void](Stop-Share) }; $nextState = [DateTime]::MinValue }
        elseif ($IDS.ContainsKey($cmd)) { [void](Invoke-Teams $cmd); $nextState = [DateTime]::MinValue }
        else { Write-Log "Unbekannter Befehl '$cmd'" }
      }
    }
    # Zustand an Companion (nur Aenderungen, alle 30 s komplett)
    if ([DateTime]::Now -ge $nextState) {
      $nextState = [DateTime]::Now.AddMilliseconds(1000)
      $s = Get-TeamsState
      if ($s.Menue) { Start-Sleep -Milliseconds 250; continue }   # Teilen-Menue offen: Zustand gerade nicht lesbar
      $neu = @{ r5_t_in = [int]$s.In; r5_t_mute = [int]$s.Mute; r5_t_video = [int]$s.Video; r5_t_mode = $(if ($Teilen) { 'teilen' } else { 'kamera' }) }
      $alle = ([DateTime]::Now - $lastPush).TotalSeconds -ge 30
      foreach ($k in $neu.Keys) {
        if ($alle -or $last[$k] -ne $neu[$k]) { if (Set-Var $k ([string]$neu[$k])) { $last[$k] = $neu[$k] } }
      }
      if ($alle) { $lastPush = [DateTime]::Now }
      # Meeting von anderen beendet oder in Teams selbst verlassen -> Abschlussfenster ebenfalls schliessen
      if (([DateTime]::Now - $script:lastObs).TotalSeconds -ge 30) {
        $script:lastObs = [DateTime]::Now; Ensure-Obs
        # Modus teilen: nach OBS-Neustart fehlt der Projektor -> Teams wuerde einen leeren Bildschirm teilen
        if ($Teilen -and $s.Share -and (Get-Process obs64 -ErrorAction SilentlyContinue)) { [void](Ensure-Projector) }
      }
      if (([DateTime]::Now - $script:lastClose).TotalSeconds -ge 5) { $script:lastClose = [DateTime]::Now; Close-AfterMeeting }
      if ($s.In -ne $script:warIn) { Write-Log $(if ($s.In) { 'Teams-Meeting erkannt' } else { 'kein Teams-Meeting' }); $script:warIn = $s.In }
    }
    if ($Teilen) { Protect-ShareScreen }
  } catch {
    Write-Log ('Fehler: ' + $_.Exception.Message); $script:win = $null; Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 250
}
