# Raumsteuerung Sitzungszimmer 5 - Teams-Meeting vom Tablet bedienen (Mikro, Bild, Verlassen)
#
# Ohne Teams-API: liest und drueckt die Buttons im Teams-Meetingfenster per Windows UI Automation
# (dieselbe Schnittstelle, die Bildschirmleser nutzen). Die Buttons haben feste Kennungen
# (microphone-button, video-button, hangup-button), unabhaengig von der Sprache.
#   - Zustand -> Companion-Variablen r5_t_in (im Meeting), r5_t_mute (stumm), r5_t_video (Bild an)
#   - Befehl  <- Companion-Variable r5_tcmd (mute | video | leave), wird nach dem Ausfuehren geleert
# Muss in der Sitzung des angemeldeten Benutzers laufen (nicht als SYSTEM) - Aufgabe "bei Anmeldung".
#
# Aufruf:
#   .\teams-steuerung.ps1            dauerhaft (startet per Aufgabenplanung)
#   .\teams-steuerung.ps1 -Status    einmal Zustand anzeigen (Test)
#   .\teams-steuerung.ps1 -Befehl mute   einmal Mikro umschalten (Test, ohne Companion)
param(
  [switch]$Status,
  [ValidateSet('', 'mute', 'video', 'leave')][string]$Befehl = '',
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
  $name = $b.Current.Name
  $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  Start-Sleep -Milliseconds 400
  if ($warMin -and -not [Fenster]::IsIconic($h)) { [void][Fenster]::ShowWindow($h, 6) }      # 6 = SW_MINIMIZE
  # nur ein sichtbares, nicht minimiertes Fenster zurueckholen (sonst taucht z. B. das versteckte Companion-Fenster auf)
  if ($vorne -ne [IntPtr]::Zero -and $vorne -ne $h -and [Fenster]::IsWindowVisible($vorne) -and -not [Fenster]::IsIconic($vorne) -and
      [Fenster]::GetForegroundWindow() -ne $vorne) { [void][Fenster]::SetForegroundWindow($vorne) }
  Write-Log ("Befehl {0}: '{1}' gedrueckt" -f $cmd, $name)
  if ($cmd -eq 'leave') { $script:win = $null }
  return $true
}

# ---------- Testaufrufe ----------
if ($Status) { $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}' -f $s.In, $s.Mute, $s.Video; exit 0 }
if ($Befehl) { [void](Invoke-Teams $Befehl); Start-Sleep -Milliseconds 800; $s = Get-TeamsState; 'Im Meeting: {0}  Mikro stumm: {1}  Bild an: {2}' -f $s.In, $s.Mute, $s.Video; exit 0 }

# ---------- Hauptschleife ----------
Write-Log ('Start Teams-Steuerung, Companion ' + $Companion + ', Benutzer ' + $env:USERNAME)
$last = @{}; $lastPush = [DateTime]::MinValue; $nextState = [DateTime]::MinValue; $companionOk = $true
while ($true) {
  try {
    # Befehl vom Tablet / Stream Deck
    $cmd = Get-Var 'r5_tcmd'
    if ($null -eq $cmd) { if ($companionOk) { Write-Log 'Companion nicht erreichbar'; $companionOk = $false } }
    else {
      if (-not $companionOk) { Write-Log 'Companion wieder erreichbar'; $companionOk = $true; $last = @{} }
      if ($cmd) {
        [void](Set-Var 'r5_tcmd' '')          # zuerst leeren: ein Tippen = ein Druck
        if ($IDS.ContainsKey($cmd)) { [void](Invoke-Teams $cmd); $nextState = [DateTime]::MinValue }
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
      if ($s.In -ne $script:warIn) { Write-Log $(if ($s.In) { 'Teams-Meeting erkannt' } else { 'kein Teams-Meeting' }); $script:warIn = $s.In }
    }
  } catch {
    Write-Log ('Fehler: ' + $_.Exception.Message); $script:win = $null; Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 250
}
