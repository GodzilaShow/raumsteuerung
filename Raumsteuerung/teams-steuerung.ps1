# Raumsteuerung Sitzungszimmer 5 - Teams-Meeting vom Tablet bedienen (Mikro, Kamera, Praesentation, Verlassen)
#
# Ohne Teams-API: liest und drueckt die Buttons im Teams-Meetingfenster per Windows UI Automation
# (dieselbe Schnittstelle, die Bildschirmleser nutzen). Die Buttons haben feste Kennungen
# (microphone-button, video-button, hangup-button), unabhaengig von der Sprache.
#   - Zustand -> Companion-Variablen r5_t_in (im Meeting), r5_t_mute (stumm), r5_t_video (Kamera an)
#   - Befehl  <- Companion-Variable r5_tcmd (mute | video | leave | join, vom Tablet: mic_on/mic_off/video_on/
#               video_off = Zielzustand), wird nach dem Ausfuehren geleert
#   - join: oeffnet den festen Meeting-Link des Raums (teams-link.txt), Kamera + Mikro an, "Jetzt teilnehmen",
#           das Meetingfenster bleibt offen (eigener Monitor am Sprecherplatz). Fortschritt in r5_t_status
#           ("start" waehrend des Beitritts, "fehler: ..." wenn es nicht klappt, sonst leer).
# Modus "teilen" (Standard, siehe unten): Teams bekommt das OBS-Bild nicht ueber die Virtuelle Kamera, sondern
#   als geteilter Bildschirm (OBS-Vollbild-Projektor auf einem virtuellen Bildschirm). Teilen per share_on/share_off
#   ("Präsentation zeigen"), video_on/video_off = Teams-Kamera, leave beendet vorher das Teilen.
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
# (powershell.exe ist schon "system aware" -> die Prozess-Einstellung greift nicht, die Thread-Einstellung schon)
Add-Type -Namespace Dpi -Name Api -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v); [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr v);'
[void][Dpi.Api]::SetProcessDpiAwarenessContext([IntPtr](-4))   # PER_MONITOR_AWARE_V2
[void][Dpi.Api]::SetThreadDpiAwarenessContext([IntPtr](-4))
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
  // Grafik-Ausgang, dessen Treibername "name" enthaelt (z. B. "Virtual Display Driver"): "DISPLAYname|1" (1 = auf
  // dem Desktop aktiv, 0 = vorhanden, aber abgeschaltet) oder "" wenn es ihn nicht gibt (Treiber fehlt/deaktiviert)
  public static string Adapter(string name) {
    for (int i = 0; i < 32; i++) {
      var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
      if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
      if (dd.DeviceString != null && dd.DeviceString.IndexOf(name, StringComparison.OrdinalIgnoreCase) >= 0)
        return dd.DeviceName + "|" + ((dd.StateFlags & 1) != 0 ? "1" : "0");
    }
    return "";
  }
  // Bildschirme frisch von Windows (Screen.AllScreens aus .NET merkt sich die Liste und kennt Umstellungen nicht)
  [StructLayout(LayoutKind.Sequential)] public struct RC { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MI { public int cb; public RC rc, work; public int flags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name; }
  public delegate bool MonCb(IntPtr h, IntPtr dc, ref RC r, IntPtr d);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonCb cb, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr h, ref MI mi);
  public static string[] Bildschirme() {   // je "DISPLAYname|x|y|w|h|primaer"
    var l = new System.Collections.Generic.List<string>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr dc, ref RC r, IntPtr d) => {
      var mi = new MI(); mi.cb = Marshal.SizeOf(mi);
      if (GetMonitorInfo(h, ref mi)) l.Add(mi.name + "|" + mi.rc.L + "|" + mi.rc.T + "|" + (mi.rc.R - mi.rc.L) + "|" + (mi.rc.B - mi.rc.T) + "|" + (mi.flags & 1));
      return true; }, IntPtr.Zero);
    return l.ToArray();
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr h, int flags, IntPtr p);
  [DllImport("user32.dll")] static extern int ChangeDisplaySettingsEx(IntPtr dev, IntPtr dm, IntPtr h, int flags, IntPtr p);
  // Bildschirm an x,y mit w x h auf den Desktop legen (0 = ok)
  public static int Platzieren(string dev, int x, int y, int w, int h) {
    var dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
    EnumDisplaySettings(dev, -2, ref dm);   // ENUM_REGISTRY_SETTINGS
    dm.dmPositionX = x; dm.dmPositionY = y; dm.dmPelsWidth = w; dm.dmPelsHeight = h; dm.dmFields = 0x20 | 0x80000 | 0x100000;
    int r = ChangeDisplaySettingsEx(dev, ref dm, IntPtr.Zero, 0x10000001, IntPtr.Zero);   // UPDATEREGISTRY | NORESET
    ChangeDisplaySettingsEx(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    return r;
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
  [DllImport("user32.dll", EntryPoint="ClipCursor")] static extern bool ClipCursorNull(IntPtr r);
  public static void MausFrei() { ClipCursorNull(IntPtr.Zero); }
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
#             Meeting-Start nur mit Kamera ("Nur Redner"); Teilen ueber "Präsentation zeigen" am Tablet (share_on/off,
#             Zustand r5_t_share). "Kamera an/aus" = Teams-Kamera.
#   teamsBild "kamera": wie bisher ueber die Virtuelle Kamera von OBS.
#   teilenTon true/false: "Sound einschliessen" (Ton von Videos in der Praesentation) - Standard an.
#   teilenBildschirm: Teil des Monitornamens des Teilen-Bildschirms, Standard "MTT" (Virtual Display Driver);
#             nicht gefunden -> der letzte Bildschirm, der nicht der Hauptbildschirm ist.
$Teilen = -not ($cfg -and $cfg.teamsBild -eq 'kamera')
$TeilenTon = -not ($cfg -and $cfg.teilenTon -eq $false)
$TeilenName = if ($cfg -and $cfg.teilenBildschirm) { $cfg.teilenBildschirm } else { 'MTT' }
#   teamsBildschirm: Teil des Monitornamens, auf dem Teams immer liegen soll (Sprecherplatz-Monitor). Ohne Angabe:
#             der erste Bildschirm, der weder Haupt- noch Teilen-Bildschirm ist; gibt es keinen, bleibt Teams, wo es ist.
$TeamsName = if ($cfg -and $cfg.teamsBildschirm) { $cfg.teamsBildschirm } else { '' }
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
  # Fenster kann inzwischen zu sein (z. B. beim Verlassen) -> dann einfach das erste
  try {
    $offen = @($treffer | Where-Object { -not [Fenster]::IsIconic([IntPtr]$_.Current.NativeWindowHandle) })
    $script:win = if ($offen.Count) { $offen | Sort-Object { $_.Current.BoundingRectangle.Width } | Select-Object -First 1 } else { $treffer[0] }
  } catch { $script:win = $treffer[0] }
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
    # Teams-Kamera an (auch im Modus "teilen"; ob geteilt wird, steht in Share)
    Video = [bool]($cam -and $cam.Current.Name -notmatch $AUS)
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
function Get-Screens {
  # frisch von Windows, nicht aus dem .NET-Zwischenspeicher (der kennt Umstellungen der Anzeige nicht)
  foreach ($z in [Fenster]::Bildschirme()) {
    $t = $z -split '\|'
    [pscustomobject]@{ DeviceName = $t[0]; Bounds = (New-Object System.Drawing.Rectangle ([int]$t[1]), ([int]$t[2]), ([int]$t[3]), ([int]$t[4])); Primary = ($t[5] -eq '1') }
  }
}
function Get-ShareScreen {
  # Bildschirm fuer das Teilen NUR nach Namen: Monitorname enthaelt $TeilenName (Virtual Display Driver: "VDD by MTT";
  # HDMI-Dummy: teilenBildschirm in mikro-automatik.json). Kein Raten - sonst wuerde ein echter Monitor (Sprecherplatz,
  # Raum-Display) zum Teilen-Bildschirm: Projektor darauf, Maus gesperrt, Fenster weggeschoben.
  $alle = @(Get-Screens)
  for ($i = 0; $i -lt $alle.Count; $i++) {
    if ([Fenster]::Monitor($alle[$i].DeviceName) -like "*$TeilenName*") { return @{ Index = $i; Bounds = $alle[$i].Bounds; Device = $alle[$i].DeviceName } }
  }
  return $null
}
function Repair-ShareScreen {
  # Fehlt der Teilen-Bildschirm, hat Windows den virtuellen Bildschirm meist nur abgeschaltet (Neustart, Win+P,
  # Monitor an-/abgesteckt). Dann: Anzeige erweitern und ihn ganz rechts mit 1920x1080 wieder hinlegen.
  # Hoechstens alle 2 min ein Versuch. Ist der Treiber weg/deaktiviert, geht das nur mit Administratorrechten.
  if ($TeilenName -ne 'MTT') { return $null }   # HDMI-Dummy u. ae.: nichts zu reparieren
  if (([DateTime]::Now - $script:lastRepair).TotalSeconds -lt 120) { return $null }
  $script:lastRepair = [DateTime]::Now
  $a = [Fenster]::Adapter('Virtual Display Driver')
  if (-not $a) { Write-Log 'Teilen-Bildschirm fehlt: Virtual Display Driver nicht vorhanden oder deaktiviert (Geraete-Manager / VDD Control, Administrator)'; return $null }
  $dev, $aktiv = $a -split '\|'
  if ($aktiv -ne '1') {
    Write-Log "Teilen-Bildschirm abgeschaltet ($dev) -> Anzeige erweitern"
    Start-Process DisplaySwitch.exe '/extend' -Wait; Start-Sleep -Seconds 3
  }
  $rechts = 0; foreach ($x in @(Get-Screens)) { if ($x.DeviceName -ne $dev) { $rechts = [Math]::Max($rechts, $x.Bounds.Right) } }
  $r = [Fenster]::Platzieren($dev, $rechts, 0, 1920, 1080); Start-Sleep -Seconds 2
  $s = Get-ShareScreen
  if ($s) { Write-Log "Teilen-Bildschirm wieder da ($dev, ganz rechts, 1920x1080)"; $script:ruheBis = [DateTime]::Now.AddSeconds(8) } else { Write-Log "Teilen-Bildschirm liess sich nicht wiederherstellen ($dev, Ergebnis $r)" }
  return $s
}
$script:lastRepair = [DateTime]::MinValue; $script:lastReopen = [DateTime]::MinValue; $script:ruheBis = [DateTime]::MinValue
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
  $s = Get-ShareScreen
  if (-not $s) {
    # kein Teilen-Bildschirm: nichts sperren, nichts schieben (Maus-Sperre von vorher aufheben); Wiederherstellung versuchen
    if ($script:hatteSchutz) { [Schutz]::MausFrei(); $script:hatteSchutz = $false; Write-Log 'Teilen-Bildschirm fehlt - Maus-Sperre aufgehoben' }
    [void](Repair-ShareScreen); return
  }
  $script:hatteSchutz = $true
  $frei = [System.Drawing.Rectangle]::Empty
  foreach ($x in @(Get-Screens)) {
    if ($x.Bounds -eq $s.Bounds) { continue }
    $frei = if ($frei.IsEmpty) { $x.Bounds } else { [System.Drawing.Rectangle]::Union($frei, $x.Bounds) }
  }
  if ($frei.IsEmpty -or $frei.IntersectsWith($s.Bounds)) {
    # Teilen-Bildschirm liegt zwischen zwei echten Monitoren -> Maus nur auf dem Hauptbildschirm moeglich
    if (-not $script:warnLage) { Write-Log 'Teilen-Bildschirm liegt zwischen den Monitoren - in den Anzeigeeinstellungen ganz nach rechts schieben (sonst kommt die Maus nicht auf die anderen Monitore)'; $script:warnLage = $true }
    $frei = (@(Get-Screens) | Where-Object Primary | Select-Object -First 1).Bounds
  } else { $script:warnLage = $false }
  [Schutz]::Maus($frei.X, $frei.Y, $frei.Width, $frei.Height)
  if (([DateTime]::Now - $script:lastSchutz).TotalMilliseconds -lt 1000) { return }
  $script:lastSchutz = [DateTime]::Now
  # Projektor-Suche per UI Automation ist teuer -> nur alle 5 s, dazwischen das gemerkte Fenster
  if (([DateTime]::Now - $script:lastProj).TotalSeconds -ge 5) {
    $script:lastProj = [DateTime]::Now
    Close-OtherProjectors $s.Bounds
    [void](Fix-Projectors $s)
    $p = Find-Projector $s.Bounds
    if (-not $p -and (Get-Process obs64 -ErrorAction SilentlyContinue)) { [void](Ensure-Projector); $p = Find-Projector $s.Bounds }
    # Projektor muss den Teilen-Bildschirm ganz fuellen (nach dem Wiederherstellen rechnet Windows die Groesse
    # zwischen 125 % und 100 % um -> sonst saehe Teams einen Rand vom leeren Desktop)
    if ($p) {
      $r = $p.Current.BoundingRectangle; $b = $s.Bounds
      if ([int]$r.X -ne $b.X -or [int]$r.Y -ne $b.Y -or [int]$r.Width -ne $b.Width -or [int]$r.Height -ne $b.Height) {
        $hp = [IntPtr]$p.Current.NativeWindowHandle
        for ($k = 0; $k -lt 2; $k++) { [void][Fenster]::SetWindowPos($hp, [IntPtr](-1), $b.X, $b.Y, $b.Width, $b.Height, 0x10); Start-Sleep -Milliseconds 300 }
        $r2 = $p.Current.BoundingRectangle
        if ([int]$r2.Width -eq $b.Width -and [int]$r2.Height -eq $b.Height) { Write-Log "Teilen: OBS-Projektor auf volle Groesse gebracht ($([int]$r.Width)x$([int]$r.Height) -> $($b.Width)x$($b.Height))" }
        elseif ([DateTime]::Now -ge $script:ruheBis -and ([DateTime]::Now - $script:lastReopen).TotalSeconds -ge 120) {   # hoechstens alle 2 min, nie in Schleife
          $script:lastReopen = [DateTime]::Now
          # OBS haelt die alte Groesse fest (kennt den wiederhergestellten Bildschirm noch nicht neu) -> schliessen, neu oeffnen
          Write-Log "Teilen: OBS-Projektor hat falsche Groesse ($([int]$r2.Width)x$([int]$r2.Height)) -> neu oeffnen"
          try { $p.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch { }
          Start-Sleep -Milliseconds 800; $script:lastOpen = [DateTime]::MinValue; [void](Ensure-Projector)
          $p = Find-Projector $s.Bounds   # das alte Fenster ist zu
        }
      }
    }
    $script:projHwnd = [IntPtr]::Zero; if ($p) { try { $script:projHwnd = [IntPtr]$p.Current.NativeWindowHandle } catch { } }
  }
  $h = $script:projHwnd
  # Teams-Rahmen/-Leiste beim Teilen; OBS-Projektoren nie verschieben (Vollbild auf dem Hauptbildschirm wuerde ihn verdecken)
  $erlaubt = [uint32[]]@(Get-Process ms-teams, obs64 -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
  foreach ($k in [Schutz]::Fenster($s.Bounds.X, $s.Bounds.Y, $s.Bounds.Width, $s.Bounds.Height, $frei.X, $frei.Y, $frei.Width, $frei.Height, $h, $erlaubt)) { Write-Log "Teilen-Bildschirm: Fenster ($k) zurueck auf den Hauptbildschirm" }
}
function Get-TeamsScreen {
  $alle = @(Get-Screens); $teilen = Get-ShareScreen
  if ($TeamsName) { foreach ($x in $alle) { if ([Fenster]::Monitor($x.DeviceName) -like "*$TeamsName*") { return $x.Bounds } } }
  foreach ($x in $alle) { if (-not $x.Primary -and -not ($teilen -and $x.Bounds -eq $teilen.Bounds)) { return $x.Bounds } }
  return $null
}
function Place-Teams {
  # Teams-Fenster (Meeting, Hauptfenster) auf den Sprecherplatz-Monitor, maximiert. Minimierte Fenster (z. B. beim
  # Teilen) und die Teilen-Leiste/-Rahmen auf dem Teilen-Bildschirm bleiben, wie sie sind.
  $ziel = Get-TeamsScreen; if (-not $ziel) { return }
  $teilen = Get-ShareScreen
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      $h = [IntPtr]$w.Current.NativeWindowHandle; $r = $w.Current.BoundingRectangle
      if ([Fenster]::IsIconic($h) -or -not [Fenster]::IsWindowVisible($h) -or $r.Width -lt 600 -or $r.Height -lt 400) { continue }
      if ($teilen -and (In-Bounds $r $teilen.Bounds)) { continue }
      if (In-Bounds $r $ziel) { continue }
      [void][Fenster]::ShowWindow($h, 9)   # SW_RESTORE
      [void][Fenster]::SetWindowPos($h, [IntPtr]::Zero, $ziel.X + 50, $ziel.Y + 50, [Math]::Min(1600, $ziel.Width - 100), [Math]::Min(900, $ziel.Height - 100), 0x14)
      [void][Fenster]::ShowWindow($h, 3)   # SW_MAXIMIZE auf dem Ziel-Monitor
      Write-Log "Teams-Fenster '$(($w.Current.Name -split ' \| ')[0])' auf den Sprecherplatz-Monitor gelegt"
    } catch { }
  }
}
$script:lastPlace = [DateTime]::MinValue; $script:lastOpen = [DateTime]::MinValue
$script:lastSchutz = [DateTime]::MinValue; $script:lastProj = [DateTime]::MinValue; $script:projHwnd = [IntPtr]::Zero
function Fix-Projectors($s) {
  # Regel: ein OBS-Projektor darf NIE auf einem echten Monitor bleiben (er wuerde ihn ganz verdecken).
  # Liegt er woanders -> auf den Teilen-Bildschirm schieben (zweimal: Windows rechnet 125 %/100 % um); klappt das
  # nicht -> schliessen. Gibt zurueck, ob danach einer auf dem Teilen-Bildschirm liegt.
  $obs = @(Get-Process obs64 -ErrorAction SilentlyContinue).Id; $b = $s.Bounds; $da = $false
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($obs -notcontains $w.Current.ProcessId -or $w.Current.Name -notmatch '(?i)^(projektor|projector)') { continue }
      if (In-Bounds $w.Current.BoundingRectangle $b) { $da = $true; continue }
      $h = [IntPtr]$w.Current.NativeWindowHandle; $alt = $w.Current.BoundingRectangle
      for ($k = 0; $k -lt 2; $k++) { [void][Fenster]::SetWindowPos($h, [IntPtr](-1), $b.X, $b.Y, $b.Width, $b.Height, 0x10); Start-Sleep -Milliseconds 300 }
      if (In-Bounds $w.Current.BoundingRectangle $b) { Write-Log "Teilen: OBS-Projektor von $alt auf den Teilen-Bildschirm geholt"; $da = $true }
      else { $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Write-Log "Teilen: OBS-Projektor lag auf einem echten Monitor ($alt) und liess sich nicht verschieben -> geschlossen" }
    } catch { }
  }
  return $da
}
function Ensure-Projector {
  # OBS-Programm als Vollbild-Projektor auf dem Teilen-Bildschirm (Companion-Button 1/3/9, Monitor-Nr. in r5_proj_mon;
  # OBS zaehlt die Bildschirme in derselben Reihenfolge wie Windows)
  $s = Get-ShareScreen
  if (-not $s) { $script:lastRepair = [DateTime]::MinValue; $s = Repair-ShareScreen }   # beim Tippen sofort versuchen
  if (-not $s) { Write-Log "Teilen: kein Teilen-Bildschirm ('$TeilenName') - bitte am Rednerplatz in Teams von Hand teilen"; $script:keinSchirm = $true; return $null }
  $script:keinSchirm = $false
  if (Find-Projector $s.Bounds) { return $s }
  # Nie einen zweiten "Inhalt"-Projektor oeffnen (z. B. wenn er nach dem Umstellen der Bildschirme woanders liegt)
  $obs = @(Get-Process obs64 -ErrorAction SilentlyContinue).Id
  $da = @()
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try { if ($obs -contains $w.Current.ProcessId -and $w.Current.Name -match '(?i)^(projektor|projector)' -and $w.Current.Name -match $PROJ) { $da += $w } } catch { }
  }
  if ($da.Count) {
    # liegt woanders (z. B. nach Abschalten des Teilen-Bildschirms auf dem Hauptbildschirm) -> holen oder schliessen
    if (Fix-Projectors $s) { return $s }
  }
  if ([DateTime]::Now -lt $script:ruheBis) { return $null }   # OBS kennt den eben wiederhergestellten Bildschirm noch nicht
  $script:warnProj = $false
  if (([DateTime]::Now - $script:lastOpen).TotalSeconds -lt 120) { return $null }   # hoechstens alle 2 min einer
  $script:lastOpen = [DateTime]::Now
  Close-OtherProjectors $s.Bounds
  # OBS zaehlt die Bildschirme anders als Windows: Hauptbildschirm zuerst, dann die uebrigen in Windows-Reihenfolge
  $obsNr = 0; foreach ($x in @(@(Get-Screens) | Sort-Object { -not $_.Primary })) { if ($x.DeviceName -eq $s.Device) { break }; $obsNr++ }
  [void](Set-Var 'r5_proj_mon' ([string]$obsNr))
  try { [void](Invoke-Companion 'POST' '/api/location/1/3/9/press') } catch { }
  for ($i = 0; $i -lt 10 -and -not (Find-Projector $s.Bounds); $i++) { Start-Sleep -Milliseconds 500 }
  if (-not (Find-Projector $s.Bounds)) { [void](Fix-Projectors $s) }   # auf falschem Monitor aufgegangen -> holen/schliessen
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
function Set-PeopleScene([switch]$Immer) {
  # Beim Teilen kommt die Praesentation getrennt -> die Kamera soll Personen zeigen, nicht noch einmal die Folien.
  # -Immer (Meeting-Start): unabhaengig von der letzten Szene auf "Nur Redner"
  for ($i = 0; $i -lt 4; $i++) {   # langsamer PC: Companion antwortet evtl. erst beim zweiten Versuch
    try {
      $sc = (Invoke-Companion 'GET' '/api/variable/obs/scene_active/value').Trim()
      if (-not $Immer -and $sc -notin 'Alles im Blick', 'Folien Groß', 'Folien groß') { return }
      if ($sc -eq 'Nur Redner') { return }
      [void](Invoke-Companion 'POST' '/api/location/1/1/4/press'); Write-Log "Teilen: Kamera-Szene '$sc' -> 'Nur Redner'"; return
    } catch { Start-Sleep -Milliseconds 700 }
  }
  Write-Log 'Teilen: Kamera-Szene nicht umgeschaltet (Companion antwortet nicht)'
}
function Stop-Share {
  $w = Find-Meeting; if (-not $w) { return $false }
  $b = $w.FindFirst($Scope::Descendants, (Cond 'share-button'))
  if (-not $b -or $b.Current.Name -notmatch $TEILT) { return $true }
  $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Milliseconds 300; $b = $w.FindFirst($Scope::Descendants, (Cond 'share-button')); if ($b -and $b.Current.Name -notmatch $TEILT) { break } }
  Write-Log 'Teilen beendet'; return $true
}
$EintragDatei = Join-Path $PSScriptRoot 'teilen-eintrag.txt'
function Get-ShareEntry([int]$anzahl) {
  try { foreach ($z in Get-Content $EintragDatei -ErrorAction Stop) { if ($z -match "^$anzahl=(\d+)$") { return [int]$Matches[1] } } } catch { }
  return $null
}
function Set-ShareEntry([int]$anzahl, [int]$nr) {
  try {
    $alt = @(Get-Content $EintragDatei -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^$anzahl=" })
    Set-Content -Path $EintragDatei -Value (@($alt) + "$anzahl=$nr") -Encoding ASCII
  } catch { }
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
  # Bildschirme im Menue heissen alle gleich ("Generic PnP Monitor") und Teams' Reihenfolge passt nicht immer zu
  # Windows. Deshalb: zuerst der Eintrag, der beim letzten Mal richtig war (teilen-eintrag.txt, je Anzahl der
  # Bildschirme), dann der mit der Windows-Nummer, dann die uebrigen; an der Lage der Teams-Leiste pruefen, ob es
  # stimmt. Ein falscher Versuch zeigt den Teilnehmern kurz einen anderen Bildschirm - daher das Merken.
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
    $gemerkt = Get-ShareEntry $items.Count
    $reihe = @(@($gemerkt) + @($s.Index) + @(($items.Count - 1)..0) | Where-Object { $null -ne $_ } | Select-Object -Unique)
    $nr = $reihe | Where-Object { $_ -lt $items.Count -and $probiert -notcontains $_ } | Select-Object -First 1
    if ($null -eq $nr) { Write-Log 'Teilen: Teilen-Bildschirm nicht in der Teams-Liste'; return $false }
    $probiert += $nr
    $items[$nr].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $bar = $null; for ($i = 0; $i -lt 20 -and -not ($bar = Find-ShareBar); $i++) { Start-Sleep -Milliseconds 300 }
    if ($bar -and (In-Bounds $bar.Current.BoundingRectangle $s.Bounds)) {
      Write-Log "Teilen: Bildschirm $($s.Index) wird geteilt (Eintrag $($nr + 1) von $($items.Count), Ton $(if ($TeilenTon) { 'an' } else { 'aus' }))"
      Set-ShareEntry $items.Count $nr
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
  # Start nur mit Kamera, immer "Nur Redner"; die Praesentation teilt erst der Knopf "Präsentation zeigen" (share_on)
  Set-PeopleScene -Immer
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
      # zuerst leeren: ein Tippen = ein Druck. Klappt das Leeren nicht, nicht ausfuehren - sonst kaeme derselbe
      # Befehl alle 250 ms wieder (mute/video wuerden hin- und herschalten); naechste Runde neu versuchen
      if ($cmd -and -not (Set-Var 'r5_tcmd' '')) { if (-not $script:warnLeer) { Write-Log "Befehl ${cmd}: r5_tcmd laesst sich nicht leeren - nicht ausgefuehrt"; $script:warnLeer = $true }; $cmd = '' }
      elseif ($cmd) { $script:warnLeer = $false }
      if ($cmd) {
        if ($cmd -eq 'join') { [void](Join-Teams); $nextState = [DateTime]::MinValue }
        elseif ($cmd -match '^(mic|video)_(on|off)$') {
          # Zielzustand statt Umschalten (vom Tablet): nur druecken, wenn Teams anders steht -> verlorene oder
          # doppelte Befehle koennen den Zustand nicht verdrehen
          $was = $Matches[1]; $soll = $Matches[2] -eq 'on'
          $s = Get-TeamsState
          $ist = if ($was -eq 'mic') { -not $s.Mute } else { $s.Video }
          if (-not $s.In) { Write-Log "Befehl ${cmd}: kein Teams-Meeting offen" }
          elseif ($ist -ne $soll) { [void](Invoke-Teams $(if ($was -eq 'mic') { 'mute' } else { 'video' })) }
          else { Write-Log "Befehl ${cmd}: Teams steht schon so" }
          $nextState = [DateTime]::MinValue
        }
        elseif ($cmd -in 'share_on', 'share_off') {
          if ($cmd -eq 'share_off') { [void](Stop-Share); if ((Get-Var 'r5_t_status') -like 'fehler*') { [void](Set-Var 'r5_t_status' '') } }
          elseif (Start-Share) { [void](Set-Var 'r5_t_status' ''); Set-PeopleScene }
          else { [void](Set-Var 'r5_t_status' $(if ($script:keinSchirm) { 'fehler: kein Teilen-Bildschirm' } else { 'fehler: Präsentation teilen' })) }
          $nextState = [DateTime]::MinValue
        }
        elseif ($IDS.ContainsKey($cmd)) { [void](Invoke-Teams $cmd); $nextState = [DateTime]::MinValue }
        else { Write-Log "Unbekannter Befehl '$cmd'" }
      }
    }
    # Zustand an Companion (nur Aenderungen, alle 30 s komplett)
    if ([DateTime]::Now -ge $nextState) {
      $nextState = [DateTime]::Now.AddMilliseconds(1000)
      $s = Get-TeamsState
      if ($s.Menue) { Start-Sleep -Milliseconds 250; continue }   # Teilen-Menue offen: Zustand gerade nicht lesbar
      $neu = @{ r5_t_in = [int]$s.In; r5_t_mute = [int]$s.Mute; r5_t_video = [int]$s.Video; r5_t_share = [int]$s.Share; r5_t_mode = $(if ($Teilen) { 'teilen' } else { 'kamera' }) }
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
      if ($s.In -ne $script:warIn) {
        Write-Log $(if ($s.In) { 'Teams-Meeting erkannt' } else { 'kein Teams-Meeting' })
        # Meeting zu Ende: alte Fehlermeldung (z. B. "fehler: Präsentation teilen") nicht ins naechste Meeting mitnehmen
        if (-not $s.In -and $script:warIn) { if ((Get-Var 'r5_t_status') -like 'fehler*') { [void](Set-Var 'r5_t_status' '') } }
        $script:warIn = $s.In
      }
    }
    if ($Teilen) { Protect-ShareScreen }
    if (([DateTime]::Now - $script:lastPlace).TotalSeconds -ge 5) { $script:lastPlace = [DateTime]::Now; Place-Teams }
  } catch {
    Write-Log ('Fehler: ' + $_.Exception.Message); $script:win = $null; Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 250
}
