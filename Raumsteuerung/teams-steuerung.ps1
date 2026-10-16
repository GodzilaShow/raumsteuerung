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
# Ausserdem OBS-Waechter: startet OBS beim Anmelden und nach einem Absturz (alle 30 s geprueft).
# Muss in der Sitzung des angemeldeten Benutzers laufen (nicht als SYSTEM) - Aufgabe "bei Anmeldung".
#
# Aufruf:
#   .\teams-steuerung.ps1            dauerhaft (startet per Aufgabenplanung)
#   .\teams-steuerung.ps1 -Status    einmal Zustand anzeigen (Test)
#   .\teams-steuerung.ps1 -Befehl mute   einmal Mikro umschalten (Test, ohne Companion)
param(
  [switch]$Status,
  [ValidateSet('', 'mute', 'video', 'leave', 'join')][string]$Befehl = '',
  [string]$Companion = '',
  [string]$Log = (Join-Path $PSScriptRoot 'teams-steuerung.log')
)
$ErrorActionPreference = 'Stop'
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
}
'@

if (-not $Companion) {
  $Companion = 'http://127.0.0.1:8000'
  try { $Companion = (Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'mikro-automatik.json') | ConvertFrom-Json).companion } catch { }
}
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
  if (-not $w) { return @{ In = $false; Mute = $false; Video = $false } }
  $mic = $w.FindFirst($Scope::Descendants, (Cond $IDS.mute))
  $cam = $w.FindFirst($Scope::Descendants, (Cond $IDS.video))
  return @{
    In    = $true
    Mute  = [bool]($mic -and $mic.Current.Name -match $AUS)
    Video = [bool]($cam -and $cam.Current.Name -notmatch $AUS)
  }
}
function Invoke-Teams([string]$cmd) {
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
  $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
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
function Set-Switch($w, [string]$muster) {
  # Kamera-/Mikro-Schalter im Beitrittsfenster einschalten (Kennungen wechseln, daher per Name + TogglePattern)
  $cBtn = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  foreach ($b in $w.FindAll($Scope::Descendants, $cBtn)) {
    if ($b.Current.Name -notmatch $muster) { continue }
    try { $tp = $b.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern) } catch { continue }
    if ($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::Off) { $tp.Toggle(); Write-Log "Beitritt: '$($b.Current.Name)' eingeschaltet" }
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
        Set-Switch $pre '(?i)^kamera|camera'
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
  [void](Set-Var 'r5_t_status' '')
  return $true
}

# ---------- Testaufrufe ----------
if ($Status) { $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}' -f $s.In, $s.Mute, $s.Video; exit 0 }
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
          elseif ($ist -ne $soll) { [void](Invoke-Teams $(if ($was -eq 'mic') { 'mute' } else { 'video' })) }
          else { Write-Log "Befehl ${cmd}: Teams steht schon so" }
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
      $neu = @{ r5_t_in = [int]$s.In; r5_t_mute = [int]$s.Mute; r5_t_video = [int]$s.Video }
      $alle = ([DateTime]::Now - $lastPush).TotalSeconds -ge 30
      foreach ($k in $neu.Keys) {
        if ($alle -or $last[$k] -ne $neu[$k]) { if (Set-Var $k ([string]$neu[$k])) { $last[$k] = $neu[$k] } }
      }
      if ($alle) { $lastPush = [DateTime]::Now }
      # Meeting von anderen beendet oder in Teams selbst verlassen -> Abschlussfenster ebenfalls schliessen
      if (([DateTime]::Now - $script:lastObs).TotalSeconds -ge 30) { $script:lastObs = [DateTime]::Now; Ensure-Obs }
      if (([DateTime]::Now - $script:lastClose).TotalSeconds -ge 5) { $script:lastClose = [DateTime]::Now; Close-AfterMeeting }
      if ($s.In -ne $script:warIn) { Write-Log $(if ($s.In) { 'Teams-Meeting erkannt' } else { 'kein Teams-Meeting' }); $script:warIn = $s.In }
    }
  } catch {
    Write-Log ('Fehler: ' + $_.Exception.Message); $script:win = $null; Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 250
}
