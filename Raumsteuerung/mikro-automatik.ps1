# Raumsteuerung Sitzungszimmer 5 - Mikrofon-Automatik fuer die Publikum-Kamera
#
# Liest die Pegel der Tischmikrofone vom Yamaha RM-CR (RCP, TCP 49280, Meter) und
# schwenkt die Publikum-Kamera ueber Companion auf die Zone des sprechenden Mikrofons.
#   - Ein Mikrofon spricht          -> Zone dieses Mikrofons, r5_pmic = Nummer
#   - Zwei oder mehr gleichzeitig   -> Ganzer Raum (ausser einer ist deutlich lauter -> dessen Zone)
#   - 3 s Stille                    -> Ganzer Raum
#   - hoechstens eine Bewegung alle 4 s, optional OBS-Freeze waehrend des Schwenks
#   - nur wenn r5_pauto = 1 (Schalter "Automatisch" auf dem Tablet)
# Einstellungen: mikro-automatik.json (gleicher Ordner)
#
# Aufruf:
#   .\mikro-automatik.ps1               Automatik (laeuft dauerhaft, startet per Aufgabenplanung)
#   .\mikro-automatik.ps1 -Zuordnung    Pegel aller Kanaele live anzeigen (Mikrofon -> Kanal herausfinden)
#   .\mikro-automatik.ps1 -Trocken      Automatik nur protokollieren, nichts an Companion senden
param(
  [switch]$Zuordnung,
  [switch]$Trocken,
  [string]$Config = (Join-Path $PSScriptRoot 'mikro-automatik.json'),
  [string]$Log = (Join-Path $PSScriptRoot 'mikro-automatik.log')
)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content -Raw -Encoding UTF8 $Config | ConvertFrom-Json
if ($Zuordnung) { $Trocken = $true }   # beim Zuordnen nie etwas an Companion senden

$uhr = [System.Diagnostics.Stopwatch]::StartNew()
function Now { $uhr.ElapsedMilliseconds }   # Millisekunden seit Start (laeuft nicht ueber wie TickCount)
function Write-Log([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
  Write-Host $line
  try {
    if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 1MB) { Move-Item $Log ($Log + '.alt') -Force }
    Add-Content -Path $Log -Value $line -Encoding UTF8
  } catch { }
}

# ---------- Mikrofone / Kanaele ----------
$mics = @()   # Liste von @{ Nr; Kanaele; Zone }
foreach ($p in $cfg.mikrofone.PSObject.Properties) {
  $k = @($p.Value | ForEach-Object { [int]$_ })
  if ($k.Count -gt 0) {
    $zone = $cfg.zonen.($p.Name)
    $mics += @{ Nr = [int]$p.Name; Kanaele = $k; Zone = [string]$zone; LoudSince = 0; LastLoud = 0; Active = $false; Avg = 0 }
  }
}
$schwelle = [Convert]::ToInt32($cfg.schwelleHex, 16)
$schwelleAus = [Convert]::ToInt32($cfg.schwelleAusHex, 16)
# Zwei Mikrofone gleichzeitig: ist eines um so viele Meter-Stufen lauter (geglaettet), gilt nur dieses (0 = aus)
$vorsprung = if ($null -ne $cfg.vorsprungStufen) { [int]$cfg.vorsprungStufen } else { 8 }

# ---------- Companion (HTTP-API) ----------
function Invoke-Companion([string]$method, [string]$path) {
  $req = [System.Net.HttpWebRequest]::Create($cfg.companion + $path)
  $req.Method = $method; $req.Timeout = 1500; $req.ReadWriteTimeout = 1500
  if ($method -eq 'POST') { $req.ContentLength = 0 }
  $res = $req.GetResponse()
  try { $sr = New-Object System.IO.StreamReader($res.GetResponseStream()); return $sr.ReadToEnd() } finally { $res.Close() }
}
function Press([string]$loc, [string]$why) {
  if (-not $loc) { return }
  Write-Log ("Druecke {0}  ({1})" -f $loc, $why)
  if ($Trocken) { return }
  try { [void](Invoke-Companion 'POST' ('/api/location/' + $loc + '/press')) } catch { Write-Log ('Companion-Fehler: ' + $_.Exception.Message) }
}
function Set-CompanionVar([string]$name, [string]$value) {
  if ($Trocken) { return }
  try { [void](Invoke-Companion 'POST' ('/api/custom-variable/' + $name + '/value?value=' + $value)) } catch { Write-Log ('Companion-Fehler: ' + $_.Exception.Message) }
}
function Get-Auto {
  try { return ((Invoke-Companion 'GET' ('/api/custom-variable/' + $cfg.autoVariable + '/value')).Trim() -match '^(1|true|on)$') }
  catch { return $null }    # Companion nicht erreichbar -> nichts bewegen
}

# ---------- RM-CR (RCP) ----------
# Antwort: NOTIFY mtr RM:NeInPostFader level 61 61 60 ...   (7E = 0 dBFS; auch ohne Leerzeichen "616160...")
function Parse-Levels([string]$line) {
  $i = $line.IndexOf(' level ')
  if ($i -lt 0) { return $null }
  $hex = ($line.Substring($i + 7) -replace '[^0-9A-Fa-f]', '')
  $vals = New-Object int[] ([Math]::Floor($hex.Length / 2))
  for ($j = 0; $j -lt $vals.Length; $j++) { $vals[$j] = [Convert]::ToInt32($hex.Substring($j * 2, 2), 16) }
  return , $vals
}

$levels = @()     # letzte Pegel je Kanal (Index 0 = Kanal 1)
$peaks = @{}      # Spitzenwert je Kanal fuer die Anzeige
$state = @{ Zone = $null; Mic = -1; LastMove = -100000; LastSpeech = 0; FreezeOff = 0; Auto = $false; AutoCheck = 0 }

function Decide {
  $t = Now
  foreach ($m in $mics) {
    $lvl = 0
    foreach ($k in $m.Kanaele) { if ($k -ge 1 -and $k -le $levels.Length -and $levels[$k - 1] -gt $lvl) { $lvl = $levels[$k - 1] } }
    $m.Avg += ($lvl - $m.Avg) * 0.15   # geglaetteter Pegel fuer den Lautstaerke-Vergleich
    if ($lvl -ge $schwelle) { if ($m.LoudSince -eq 0) { $m.LoudSince = $t } } else { $m.LoudSince = 0 }
    if ($lvl -ge $schwelleAus -and ($m.Active -or $m.LoudSince -ne 0)) { $m.LastLoud = $t }
    if (-not $m.Active -and $m.LoudSince -ne 0 -and ($t - $m.LoudSince) -ge $cfg.ansprechMs) {
      $m.Active = $true; $m.LastLoud = $t
      # Wortwechsel: wer gerade nur noch "nachhaelt" (schon leise), gibt sofort ab -> kein kurzer Schwenk auf "Ganzer Raum"
      foreach ($o in $mics) { if ($o -ne $m -and $o.Active -and $o.LoudSince -eq 0) { $o.Active = $false } }
    }
    if ($m.Active -and ($t - $m.LastLoud) -ge $cfg.halteMs) { $m.Active = $false }
  }
  $act = @($mics | Where-Object { $_.Active })
  if ($act.Count -ge 2 -and $vorsprung -gt 0) {
    # Nachbarmikrofon hoert mit: deutlich lauteres Mikrofon gewinnt statt "Ganzer Raum"
    $sorted = @($act | Sort-Object { $_.Avg } -Descending)
    if (($sorted[0].Avg - $sorted[1].Avg) -ge $vorsprung) { $act = @($sorted[0]) }
  }
  if ($act.Count -eq 1) { $mic = $act[0].Nr; $zone = $act[0].Zone; $state.LastSpeech = $t }
  elseif ($act.Count -ge 2) { $mic = 0; $zone = $cfg.ganzerRaum; $state.LastSpeech = $t }
  elseif (($t - $state.LastSpeech) -ge $cfg.stilleMs) { $mic = 0; $zone = $cfg.ganzerRaum }
  else { return }   # kurze Pause beim Sprechen -> bleiben

  if ($mic -ne $state.Mic) { $state.Mic = $mic; Set-CompanionVar $cfg.micVariable $mic; Write-Log ("Aktives Mikrofon: {0}" -f $(if ($mic) { $mic } else { 'keins/mehrere' })) }
  if (-not $state.Auto -or $zone -eq $state.Zone) { return }
  if (($t - $state.LastMove) -lt $cfg.mindestAbstandMs) { return }   # spaeter erneut pruefen
  if ($cfg.freezeAn) { Press $cfg.freezeAn 'Bild einfrieren'; $state.FreezeOff = $t + $cfg.freezeMs }
  Press $zone ("Mikrofon {0}" -f $(if ($mic) { $mic } else { 'keins/mehrere -> Ganzer Raum' }))
  $state.Zone = $zone; $state.LastMove = $t
}

function Show-Levels {
  $t = Now
  $out = New-Object System.Text.StringBuilder
  [void]$out.AppendLine('Mikrofon-Zuordnung  ' + $cfg.meter + '   (Strg+C beendet)')
  [void]$out.AppendLine('Nacheinander in jedes Mikrofon sprechen und den Kanal mit Ausschlag notieren.')
  [void]$out.AppendLine(('Schwelle {0} (Sprache), Grundrauschen sollte darunter liegen. 7E = 0 dBFS' -f $cfg.schwelleHex))
  [void]$out.AppendLine('')
  for ($i = 0; $i -lt $levels.Length; $i++) {
    $v = $levels[$i]; $k = $i + 1
    if (-not $peaks.ContainsKey($k) -or $v -ge $peaks[$k].V -or ($t - $peaks[$k].T) -gt 3000) { $peaks[$k] = @{ V = $v; T = $t } }
    $bar = '#' * [Math]::Max(0, [Math]::Min(40, ($v - 0x58)))
    $mark = if ($v -ge $schwelle) { '  <-- SPRICHT' } else { '' }
    [void]$out.AppendLine(('Kanal {0,2}: {1:X2}  Spitze {2:X2}  {3,-40}{4}' -f $k, $v, $peaks[$k].V, $bar, $mark))
  }
  [void]$out.AppendLine('')
  foreach ($m in $mics) { [void]$out.AppendLine(('Mikrofon {0} = Kanal {1}  {2}' -f $m.Nr, ($m.Kanaele -join '+'), $(if ($m.Active) { 'AKTIV' } else { '' }))) }
  try { [Console]::SetCursorPosition(0, 0) } catch { }
  Write-Host ($out.ToString())
}

# ---------- Hauptschleife (mit Wiederverbinden) ----------
if ($Zuordnung) { try { Clear-Host } catch { } }
Write-Log ('Start ' + $(if ($Zuordnung) { 'Zuordnung' } elseif ($Trocken) { 'Trockenlauf' } else { 'Automatik' }) + ', Mikrofone: ' + (($mics | ForEach-Object { '' + $_.Nr + '=Kanal ' + ($_.Kanaele -join '+') }) -join ', '))
while ($true) {
  $client = $null
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $ar = $client.BeginConnect($cfg.rmcrIp, [int]$cfg.rmcrPort, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne(3000)) { throw ('RM-CR ' + $cfg.rmcrIp + ' antwortet nicht') }
    $client.EndConnect($ar)
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream); $writer.NewLine = "`n"; $writer.AutoFlush = $true
    Write-Log ('Verbunden mit RM-CR ' + $cfg.rmcrIp)
    $buf = New-Object byte[] 8192; $text = ''
    $renew = -100000; $lastData = Now   # Meter sofort starten; $lastDraw = 0
    while ($true) {
      $t = Now
      if ($t - $renew -ge 8000) { $writer.WriteLine(('mtrstart {0} {1}' -f $cfg.meter, $cfg.meterIntervallMs)); $renew = $t }   # Meter laufen nur ~10 s
      if (-not $Zuordnung -and ($t - $state.AutoCheck) -ge 1000) {
        $state.AutoCheck = $t; $a = Get-Auto
        if ($a -and -not $state.Auto) { $state.Zone = $null; Write-Log 'Automatik an' }   # neu einschalten -> sofort richtige Zone
        if (-not $a -and $state.Auto) { Write-Log $(if ($null -eq $a) { 'Companion nicht erreichbar - Kamera bleibt stehen' } else { 'Automatik aus (Tablet)' }) }
        $state.Auto = [bool]$a
      }
      # Gegenstelle hat die Verbindung geschlossen (lesbar, aber keine Daten)
      if ($client.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $client.Client.Available -eq 0) { throw 'Verbindung vom RM-CR geschlossen' }
      while ($stream.DataAvailable) {
        $n = $stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { throw 'Verbindung vom RM-CR geschlossen' }
        $text += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n); $lastData = $t
      }
      while (($nl = $text.IndexOf("`n")) -ge 0) {
        $line = $text.Substring(0, $nl).Trim(); $text = $text.Substring($nl + 1)
        if ($line -like 'NOTIFY mtr *') {
          if ($line -like ('* ' + $cfg.meter + ' *')) { $v = Parse-Levels $line; if ($null -ne $v) { $levels = $v } }
        } elseif ($line -like 'ERROR*') { Write-Log ('RM-CR meldet: ' + $line) }
      }
      if ($t - $lastData -gt 15000) { throw 'Keine Meter-Daten vom RM-CR seit 15 s' }
      if ($Zuordnung) { if ($t - $lastDraw -ge 200) { Decide; Show-Levels; $lastDraw = $t } }
      else { Decide }
      if ($state.FreezeOff -and $t -ge $state.FreezeOff) { $state.FreezeOff = 0; Press $cfg.freezeAus 'Bild wieder live' }
      Start-Sleep -Milliseconds 30
    }
  } catch {
    Write-Log ('Fehler: ' + $_.Exception.Message + ' - neuer Versuch in 5 s')
    if ($state.FreezeOff) { $state.FreezeOff = 0; Press $cfg.freezeAus 'Bild wieder live' }
  } finally {
    if ($client) { $client.Close() }
  }
  Start-Sleep -Seconds 5
}
