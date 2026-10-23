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
# Modus "teilen" (Standard, siehe unten): "Präsentation zeigen" (share_on/share_off) laesst Teams einen echten
#   Bildschirm teilen (den mit der Praesentation); die Kamera (OBS Virtuelle Kamera) zeigt die Personen.
#   video_on/video_off = Teams-Kamera, leave beendet vorher das Teilen.
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
# Echte Pixel auf allen Bildschirmen (Laptop 125 %, Monitore 100 %): sonst passen Bildschirm- und Fenster-
# Koordinaten nicht zusammen (Lage der Teams-Leiste beim Teilen, Teams auf den Sprecherplatz-Monitor legen)
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
  // Monitorname + Hardware-ID zu \\.\DISPLAYn (z. B. "Generic PnP Monitor  MONITOR\VSC1234\...")
  public static string Monitor(string dev) {
    var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
    return EnumDisplayDevices(dev, 0, ref dd, 0) ? dd.DeviceString + "  " + dd.DeviceID : "";
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
}
'@
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$cfg = $null
try { $cfg = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'mikro-automatik.json') | ConvertFrom-Json } catch { }
if (-not $Companion) { $Companion = if ($cfg -and $cfg.companion) { $cfg.companion } else { 'http://127.0.0.1:8000' } }
# Wie Teams das Bild bekommt (mikro-automatik.json, optional):
#   teamsBild "teilen" (Standard): zwei Kanaele wie bei Teams Rooms. Inhalt: Teams teilt den Bildschirm mit der
#             Praesentation -> scharf und gross. Personen: Virtuelle Kamera (OBS-Programm, Szenen Nur Redner /
#             Diskussion / Pausenbild) -> fluessig.
#             Meeting-Start nur mit Kamera ("Nur Redner"); Teilen ueber "Präsentation zeigen" am Tablet (share_on/off,
#             Zustand r5_t_share). "Kamera an/aus" = Teams-Kamera.
#   teamsBild "kamera": wie bisher ueber die Virtuelle Kamera von OBS.
#   teilenTon true/false: "Sound einschliessen" (Ton von Videos in der Praesentation) - Standard an.
#   teilenBildschirm: welcher Bildschirm geteilt wird - Nummer wie in Windows (Einstellungen -> Anzeige, z. B. "2")
#             oder Teil des Monitornamens (z. B. "ViewSonic"). Ohne Angabe: der Hauptbildschirm.
$Teilen = -not ($cfg -and $cfg.teamsBild -eq 'kamera')
$TeilenTon = -not ($cfg -and $cfg.teilenTon -eq $false)
$TeilenName = if ($cfg -and $cfg.teilenBildschirm) { ([string]$cfg.teilenBildschirm).Trim() } else { '' }
#   teamsBildschirm: Teil des Monitornamens, auf dem Teams immer liegen soll (Sprecherplatz-Monitor). Ohne Angabe:
#             der erste Bildschirm, der weder Haupt- noch Teilen-Bildschirm ist; gibt es keinen, bleibt Teams, wo es ist.
$TeamsName = if ($cfg -and $cfg.teamsBildschirm) { ([string]$cfg.teamsBildschirm).Trim() } else { '' }
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
  # Fehlerantwort (404 bei fehlender Variable, 500) schliessen - sonst bleibt die Verbindung belegt und nach zwei
  # solchen laufen alle Anfragen in den Timeout ("Companion nicht erreichbar", obwohl er laeuft)
  try { $res = $req.GetResponse() } catch [System.Net.WebException] { if ($_.Exception.Response) { $_.Exception.Response.Close() }; throw }
  try { $sr = New-Object System.IO.StreamReader($res.GetResponseStream()); return $sr.ReadToEnd() } finally { $res.Close() }
}
[System.Net.ServicePointManager]::DefaultConnectionLimit = 16
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
function Close-ShareTray {
  # Offenes Teilen-Menue verdeckt die Meeting-Leiste (kein hangup-button -> Raum gilt als "nicht im Meeting",
  # Verlassen/Mikro gingen ins Leere). Erst share-button erneut druecken (klappt das Menue zu), sonst Esc.
  $t = Find-ShareTray; if (-not $t) { return }
  try { $b = $t.Win.FindFirst($Scope::Descendants, (Cond 'share-button')); if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 500 } } catch { }
  if (Find-ShareTray) {
    try { [void][Fenster]::SetForegroundWindow([IntPtr]$t.Win.Current.NativeWindowHandle); Start-Sleep -Milliseconds 200; [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); Start-Sleep -Milliseconds 400 } catch { }
  }
  Write-Log $(if (Find-ShareTray) { 'Teilen-Menue laesst sich nicht schliessen' } else { 'Teilen-Menue geschlossen' })
}
function Get-Screens {
  # frisch von Windows, nicht aus dem .NET-Zwischenspeicher (der kennt Umstellungen der Anzeige nicht)
  foreach ($z in [Fenster]::Bildschirme()) {
    $t = $z -split '\|'
    [pscustomobject]@{ DeviceName = $t[0]; Bounds = (New-Object System.Drawing.Rectangle ([int]$t[1]), ([int]$t[2]), ([int]$t[3]), ([int]$t[4])); Primary = ($t[5] -eq '1') }
  }
}
function Get-ShareScreen {
  # Bildschirm, den Teams teilt: teilenBildschirm = Windows-Nummer (\\.\DISPLAY2 -> "2") oder Teil des Monitornamens;
  # ohne Angabe der Hauptbildschirm. Ist der angegebene nicht da (Monitor aus/abgesteckt) -> $null, nicht raten.
  $alle = @(Get-Screens)
  for ($i = 0; $i -lt $alle.Count; $i++) {
    $x = $alle[$i]
    $treffer = if (-not $TeilenName) { $x.Primary }
               elseif ($TeilenName -match '^\d+$') { $x.DeviceName -match "DISPLAY$TeilenName$" }
               else { [Fenster]::Monitor($x.DeviceName) -like "*$TeilenName*" }
    if ($treffer) { return @{ Index = $i; Bounds = $x.Bounds; Device = $x.DeviceName } }
  }
  return $null
}
function In-Bounds($rect, $b) {
  $x = $rect.X + $rect.Width / 2; $y = $rect.Y + $rect.Height / 2
  return ($x -ge $b.X -and $x -lt $b.X + $b.Width -and $y -ge $b.Y -and $y -lt $b.Y + $b.Height)
}
function Get-TeamsScreen {
  # teamsBildschirm (Einstellungen der Raumsteuerung.exe): Windows-Nummer, Teil des Monitornamens, "aus" = Fenster nie verschieben;
  # leer oder nicht angeschlossen -> erster Neben-Bildschirm, der nicht geteilt wird
  if ($TeamsName -eq 'aus') { return $null }
  $alle = @(Get-Screens); $teilen = Get-ShareScreen
  if ($TeamsName) {
    foreach ($x in $alle) {
      $treffer = if ($TeamsName -match '^\d+$') { $x.DeviceName -match "DISPLAY$TeamsName$" } else { [Fenster]::Monitor($x.DeviceName) -like "*$TeamsName*" }
      if ($treffer) { return $x.Bounds }
    }
  }
  # Teilen-Bildschirm eingetragen, aber nicht gefunden (umnummeriert/aus): nicht raten - der "erste Neben-Bildschirm"
  # koennte gerade das Publikums-Display sein
  if ($TeilenName -and -not $teilen) { return $null }
  # nach Windows-Nummer, wie pruefen.ps1 und Raumsteuerung.exe
  foreach ($x in ($alle | Sort-Object { [int]($_.DeviceName -replace '\D', '') })) { if (-not $x.Primary -and -not ($teilen -and $x.Bounds -eq $teilen.Bounds)) { return $x.Bounds } }
  return $null
}
function Place-Teams {
  # Teams-Fenster (Meeting, Hauptfenster) auf den Sprecherplatz-Monitor, maximiert. Minimierte Fenster (z. B. beim
  # Teilen) und die Teilen-Leiste/-Rahmen auf dem Teilen-Bildschirm bleiben, wie sie sind.
  $ziel = Get-TeamsScreen; if (-not $ziel) { return }
  # Auf dem Teilen-Bildschirm nur waehrend des Teilens nichts anfassen (Teilen-Rahmen/Mini-Fenster); sonst gehoert
  # ein grosses Teams-Fenster dort nicht hin (das Publikum saehe das Meeting statt der Folien)
  $teilen = $null; $bar = Find-ShareBar
  if ($bar) { $teilen = @(Get-Screens | Where-Object { In-Bounds $bar.Current.BoundingRectangle $_.Bounds })[0]; if (-not $teilen) { $teilen = Get-ShareScreen } }
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
$script:lastPlace = [DateTime]::MinValue
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
  $script:keinSchirm = $false
  $w = Find-Meeting
  if (-not $w) { Write-Log 'Teilen: kein Teams-Meeting offen'; return $false }
  $s = Get-ShareScreen
  if (-not $s) { Write-Log "Teilen: Bildschirm '$TeilenName' nicht gefunden (Monitor aus?) - bitte am Rednerplatz in Teams von Hand teilen"; $script:keinSchirm = $true; return $false }
  $script:keinSchirm = $false
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
    $items = @()
    for ($i = 0; $i -lt 10 -and -not $items.Count; $i++) {   # langsamer PC: Liste ist anfangs noch leer
      $items = @($t.List.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)); if (-not $items.Count) { Start-Sleep -Milliseconds 300 }
    }
    if (-not $items.Count) { Write-Log 'Teilen: Bildschirm-Liste in Teams bleibt leer'; return $false }
    $gemerkt = Get-ShareEntry $items.Count
    $reihe = @(@($gemerkt) + @($s.Index) + @(($items.Count - 1)..0) | Where-Object { $null -ne $_ } | Select-Object -Unique)
    $nr = $reihe | Where-Object { $_ -ge 0 -and $_ -lt $items.Count -and $probiert -notcontains $_ } | Select-Object -First 1
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
  for ($i = 0; $i -lt 6 -and -not $b; $i++) { Start-Sleep -Milliseconds 300; $b = $w.FindFirst($Scope::Descendants, (Cond $IDS[$cmd])) }
  if (-not $b) { Write-Log "Befehl ${cmd}: Button $($IDS[$cmd]) nach dem Wiederherstellen nicht gefunden"; return $false }
  $name = $b.Current.Name
  # Waehrend Teams die Kamera/das Mikro umschaltet oder die Leiste umbaut, ist der Button kurz gesperrt bzw. veraltet
  # (Invoke wirft) -> kurz warten, neu suchen, noch einmal. Nur "Verlassen" kann ein Menue-Knopf sein (aufklappen,
  # Rueckfrage bestaetigt Confirm-Leave); bei den anderen gaebe Expand nur "Nicht unterstuetztes Muster".
  $ok = $false; $grund = ''
  for ($i = 0; $i -lt 4 -and -not $ok; $i++) {
    if ($i) { Start-Sleep -Milliseconds 500; $b = $w.FindFirst($Scope::Descendants, (Cond $IDS[$cmd])); if (-not $b) { $grund = 'Button weg'; continue }; $name = $b.Current.Name }
    $o = $null
    if ($b.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$o)) {
      try { $o.Invoke(); $ok = $true } catch { $grund = $_.Exception.Message }
    } else { $grund = 'kein InvokePattern' }
    if (-not $ok -and $cmd -eq 'leave' -and $b.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$o)) {
      try { $o.Expand(); Start-Sleep -Milliseconds 800; $ok = $true } catch { $grund = $_.Exception.Message }
    }
  }
  # (z. B. Mikro einschalten ohne Mikrofon in Windows - RM-CR nicht per USB angeschlossen: Teams sperrt den Button)
  if (-not $ok) { Write-Log ("Befehl ${cmd}: '$name' laesst sich nicht druecken ($grund)" + $(if ($cmd -eq 'mute') { ' - Mikrofon in Windows/Teams vorhanden?' } else { '' })); return $false }
  if ($cmd -eq 'leave') { $script:leaveZeit = [DateTime]::Now; Confirm-Leave $w }
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
function Skip-ObsCrashDialog {
  # Nach einem Absturz/Stromausfall fragt OBS trotz --disable-shutdown-check "Im abgesicherten Modus starten?" und
  # wartet. Abgesicherter Modus = ohne WebSocket -> Companion/Tablet ohne OBS. Also: "Im normalen Modus starten".
  $obs = @(Get-Process obs64 -ErrorAction SilentlyContinue).Id; if (-not $obs.Count) { return }
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($obs -notcontains $w.Current.ProcessId -or $w.Current.Name -notmatch '(?i)absturz|crash') { continue }
      $cB = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
      $b = @($w.FindAll($Scope::Descendants, $cB)) | Where-Object { $_.Current.Name -match '(?i)normalen modus|normal mode' } | Select-Object -First 1
      if ($b) { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-Log "OBS: Absturz-Abfrage -> '$($b.Current.Name)'" }
    } catch { }
  }
}
function Ensure-Obs {
  if (Get-Process obs64 -ErrorAction SilentlyContinue) { Skip-ObsCrashDialog; return }
  if (-not (Test-Path $OBS)) { if (-not $script:obsFehlt) { Write-Log "OBS nicht gefunden: $OBS"; $script:obsFehlt = $true }; return }
  $arg = '--minimize-to-tray --disable-shutdown-check'
  if ((Get-Var 'r5_room') -eq '1') { $arg += ' --startvirtualcam' }
  Start-Process -FilePath $OBS -ArgumentList $arg -WorkingDirectory (Split-Path $OBS)   # OBS braucht sein Programmverzeichnis
  Write-Log "OBS gestartet ($arg)"
  for ($i = 0; $i -lt 10; $i++) { Start-Sleep -Seconds 1; Skip-ObsCrashDialog }   # Abfrage erscheint nach 1-5 s
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
# Wartebereich (Lobby): Teams zeigt nach "Jetzt teilnehmen" z. B. "Jemand wird Sie einlassen, wenn die Besprechung
# beginnt" (Gast/nicht angemeldet, fremde Organisation, Organisator noch nicht da). Kein Fehler - der Raum wartet.
function Find-Lobby {
  $ids = @(Get-Process ms-teams -ErrorAction SilentlyContinue).Id
  $cTxt = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
  foreach ($w in $AE::RootElement.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
    try {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      foreach ($t in $w.FindAll($Scope::Descendants, $cTxt)) { if ($t.Current.Name -match '(?i)einlassen|let you in|Wartebereich|lobby') { return $w } }
    } catch { }
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
  # Nach dem Aufwachen aus dem Standby verschluckt Teams den ersten Klick manchmal (Beitrittsbildschirm bleibt
  # stehen, 23.10.: zweimal "fehlgeschlagen", Meeting kam erst 1-2 min spaeter). Steht der Beitrittsbildschirm nach
  # 10 s noch da, "Jetzt teilnehmen" erneut druecken. Insgesamt bis 75 s warten.
  $ende = [DateTime]::Now.AddSeconds(75); $w = $null; $erneut = [DateTime]::Now.AddSeconds(10)
  while (-not $w -and [DateTime]::Now -lt $ende) {
    Start-Sleep -Milliseconds 700; $w = Find-Meeting
    if (-not $w -and [DateTime]::Now -ge $erneut) {
      $erneut = [DateTime]::Now.AddSeconds(10)
      if (Find-Lobby) { break }
      $pre = Find-Prejoin
      if ($pre) { try { $pre.FindFirst($Scope::Descendants, $cJoin).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Write-Log 'Beitritt: "Jetzt teilnehmen" erneut gedrueckt' } catch { } }
    }
  }
  if (-not $w -and (Find-Lobby)) {
    # Im Wartebereich: Status "warten", die Hauptschleife meldet "im Meeting", sobald jemand den Raum einlaesst
    Write-Log 'Beitritt: im Wartebereich - wartet, bis jemand den Raum in Teams einlaesst'
    [void](Set-Var 'r5_t_status' 'warten: Wartebereich'); $script:wartenSeit = [DateTime]::Now; return $false
  }
  if (-not $w) {
    Write-Log 'Beitritt fehlgeschlagen (kein Meetingfenster)'; [void](Set-Var 'r5_t_status' 'fehler: Teams reagiert nicht')
    # Kommt das Meeting doch noch (Teams langsam), behandelt die Hauptschleife es wie "eingelassen" (Status leer,
    # "Nur Redner") - sonst stuende auf dem Tablet im laufenden Meeting weiter "Teams reagiert nicht"
    $script:spaetSeit = [DateTime]::Now
    return $false
  }
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
# Befehl, der vor dem Start liegen geblieben ist (z. B. Tablet getippt, als das Skript nicht lief), verwerfen -
# sonst tritt Teams nach der naechsten Anmeldung/Neustart unerwartet dem Meeting bei
$alt = Get-Var 'r5_tcmd'
if ($alt) { [void](Set-Var 'r5_tcmd' ''); Write-Log "Alter Befehl beim Start verworfen: $alt" }
$script:wartenSeit = $null; $script:spaetSeit = $null; $script:lastLobby = [DateTime]::MinValue; $script:leaveZeit = [DateTime]::MinValue; $script:wegSeit = $null
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
      if ($cmd -and $cmd -ne 'share_on' -and (Find-ShareTray)) { Close-ShareTray }   # sonst gilt der Raum als "nicht im Meeting"
      if ($cmd) {
        # Verlassen / Raum aus waehrend der Raum im Wartebereich steht: Wartefenster schliessen (sonst wuerde der
        # Raum spaeter noch eingelassen, obwohl er aus ist)
        if ($cmd -eq 'leave' -and -not (Get-TeamsState).In) {
          $lw = Find-Lobby
          if ($lw) { try { $lw.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Write-Log 'Wartebereich verlassen (Fenster geschlossen)' } catch { Write-Log ('Wartebereich: Fenster liess sich nicht schliessen (' + $_.Exception.Message + ')') } }
          if ($script:wartenSeit) { $script:wartenSeit = $null; [void](Set-Var 'r5_t_status' '') }
          $cmd = ''
        }
        if (-not $cmd) { }
        elseif ($cmd -eq 'join') { [void](Join-Teams); $nextState = [DateTime]::MinValue }
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
          else {
            Close-ShareTray; [void](Set-Var 'r5_t_status' $(if ($script:keinSchirm) { 'fehler: kein Teilen-Bildschirm' } else { 'fehler: Präsentation teilen' })) }
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
      if ($s.Menue) {   # Teilen-Menue offen: Zustand gerade nicht lesbar; bleibt es offen (vergessen), nach 60 s schliessen
        if (-not $script:menueSeit) { $script:menueSeit = [DateTime]::Now }
        elseif (([DateTime]::Now - $script:menueSeit).TotalSeconds -ge 60) { $script:menueSeit = $null; Close-ShareTray }
        Start-Sleep -Milliseconds 250; continue
      }
      $script:menueSeit = $null
      # Beim Umschalten des Teilens (und wenn Teams sein Fenster umbaut) ist die Meeting-Leiste ein paar Sekunden
      # weg -> kurz "kein Meeting". Nicht sofort melden, sonst springt das Tablet hin und her: erst nach 8 s am Stueck
      # (oder sofort nach eigenem "Verlassen"). Waehrend die Teilen-Leiste da ist, laeuft das Meeting sicher.
      if (-not $s.In -and $script:warIn -and ([DateTime]::Now - $script:leaveZeit).TotalSeconds -gt 20) {
        if (Find-ShareBar) { $script:wegSeit = $null; Start-Sleep -Milliseconds 250; continue }
        if (-not $script:wegSeit) { $script:wegSeit = [DateTime]::Now }
        if (([DateTime]::Now - $script:wegSeit).TotalSeconds -lt 8) { Start-Sleep -Milliseconds 250; continue }
      }
      $script:wegSeit = $null
      $neu = @{ r5_t_in = [int]$s.In; r5_t_mute = [int]$s.Mute; r5_t_video = [int]$s.Video; r5_t_share = [int]$s.Share; r5_t_mode = $(if ($Teilen) { 'teilen' } else { 'kamera' }) }
      $alle = ([DateTime]::Now - $lastPush).TotalSeconds -ge 30
      foreach ($k in $neu.Keys) {
        if ($alle -or $last[$k] -ne $neu[$k]) { if (Set-Var $k ([string]$neu[$k])) { $last[$k] = $neu[$k] } }
      }
      if ($alle) { $lastPush = [DateTime]::Now }
      # Meeting von anderen beendet oder in Teams selbst verlassen -> Abschlussfenster ebenfalls schliessen
      if (([DateTime]::Now - $script:lastObs).TotalSeconds -ge 30) {
        $script:lastObs = [DateTime]::Now; Ensure-Obs
      }
      if (([DateTime]::Now - $script:lastClose).TotalSeconds -ge 5) { $script:lastClose = [DateTime]::Now; Close-AfterMeeting }
      if ($s.In -ne $script:warIn) {
        Write-Log $(if ($s.In) { 'Teams-Meeting erkannt' } else { 'kein Teams-Meeting' })
        # Meeting zu Ende: alte Fehlermeldung (z. B. "fehler: Präsentation teilen") nicht ins naechste Meeting mitnehmen
        if (-not $s.In -and $script:warIn) { if ((Get-Var 'r5_t_status') -like 'fehler*') { [void](Set-Var 'r5_t_status' '') } }
        # Aus dem Wartebereich eingelassen -> wie nach dem Beitritt: Kamera-Szene "Nur Redner", Status leer
        if ($s.In -and $script:wartenSeit) { $script:wartenSeit = $null; Write-Log 'Beitritt: eingelassen'; Set-PeopleScene -Immer; [void](Set-Var 'r5_t_status' '') }
        # Beitritt als fehlgeschlagen gemeldet, Meeting kam aber innerhalb von 5 min doch noch
        if ($s.In -and $script:spaetSeit -and ([DateTime]::Now - $script:spaetSeit).TotalMinutes -lt 5) {
          Write-Log 'Beitritt: doch noch im Meeting'; Set-PeopleScene -Immer
          if ((Get-Var 'r5_t_status') -like 'fehler*') { [void](Set-Var 'r5_t_status' '') }
        }
        $script:spaetSeit = $null
        $script:warIn = $s.In
      }
    }
    # Wartebereich verlassen ohne Einlass (abgelehnt, Fenster geschlossen) oder zu lange (15 min) -> Fehler melden
    if ($script:wartenSeit -and -not $script:warIn -and ([DateTime]::Now - $script:lastLobby).TotalSeconds -ge 5) {
      $script:lastLobby = [DateTime]::Now
      if (-not (Find-Lobby) -or ([DateTime]::Now - $script:wartenSeit).TotalMinutes -ge 15) {
        $script:wartenSeit = $null; Write-Log 'Beitritt: nicht eingelassen'; [void](Set-Var 'r5_t_status' 'fehler: nicht eingelassen')
      }
    }
    if (([DateTime]::Now - $script:lastPlace).TotalSeconds -ge 5) { $script:lastPlace = [DateTime]::Now; Place-Teams }
  } catch {
    Write-Log ('Fehler' + $(if ($cmd) { " bei Befehl ${cmd}" } else { '' }) + ': ' + $_.Exception.Message + ' (Zeile ' + $_.InvocationInfo.ScriptLineNumber + ')'); $script:win = $null; Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 250
}
