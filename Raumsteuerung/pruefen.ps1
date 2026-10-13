# Raumsteuerung Sitzungszimmer 5 - Schnellpruefung auf dem Raum-PC (keine Administratorrechte noetig)
# Zeigt gruen/gelb/rot: Companion, OBS, RM-CR, Mikrofone, Webserver, Automatik, Netzwerk, Firewall, Audio.
# Aufruf: pruefen.cmd doppelklicken (oder .\pruefen.ps1). Aendert nichts.
param([string]$Config = (Join-Path $PSScriptRoot 'mikro-automatik.json'))
$ErrorActionPreference = 'Continue'
$cfg = $null
try { $cfg = Get-Content -Raw -Encoding UTF8 $Config | ConvertFrom-Json } catch { }
$companion = if ($cfg) { $cfg.companion } else { 'http://127.0.0.1:8000' }
$rmcrIp = if ($cfg) { $cfg.rmcrIp } else { '192.168.137.185' }
$rmcrPort = if ($cfg) { [int]$cfg.rmcrPort } else { 49280 }
$script:fehler = 0; $script:warn = 0

function Zeile([string]$stufe, [string]$was, [string]$text, [string]$tipp = '') {
  $farbe = @{ OK = 'Green'; WARN = 'Yellow'; FEHLER = 'Red'; INFO = 'Gray' }[$stufe]
  if ($stufe -eq 'FEHLER') { $script:fehler++ } elseif ($stufe -eq 'WARN') { $script:warn++ }
  Write-Host ('[{0,-6}] ' -f $stufe) -ForegroundColor $farbe -NoNewline
  Write-Host ('{0,-22} {1}' -f $was, $text)
  if ($tipp -and $stufe -ne 'OK') { Write-Host ('         -> ' + $tipp) -ForegroundColor DarkGray }
}
function Get-Http([string]$url) {
  try {
    $req = [System.Net.HttpWebRequest]::Create($url); $req.Timeout = 6000; $req.ReadWriteTimeout = 6000
    $res = $req.GetResponse()
    try { $sr = New-Object System.IO.StreamReader($res.GetResponseStream()); return @{ Code = [int]$res.StatusCode; Text = $sr.ReadToEnd() } } finally { $res.Close() }
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) { return @{ Code = [int]$_.Exception.Response.StatusCode; Text = '' } }
    return $null
  } catch { return $null }
}
function Get-Var([string]$path) { $r = Get-Http ($companion + '/api/' + $path + '/value'); if ($r -and $r.Code -eq 200) { return $r.Text.Trim() } return $null }

Write-Host ''
Write-Host 'Raumsteuerung Sitzungszimmer 5 - Pruefung' -ForegroundColor Cyan
Write-Host ('{0}   PC: {1}' -f (Get-Date -Format 'dd.MM.yyyy HH:mm'), $env:COMPUTERNAME) -ForegroundColor DarkGray
Write-Host ''

# ---------- Companion ----------
$c = Get-Http ($companion + '/')
if ($c -and $c.Code -eq 200) { Zeile OK 'Companion' $companion }
else { Zeile FEHLER 'Companion' ('nicht erreichbar unter ' + $companion) 'Companion starten (Startmenue), im Companion-Fenster muss "Running" stehen' }
if ($c) {
  if ($null -ne (Get-Var 'custom-variable/r5_pauto')) { Zeile OK 'Companion-Konfig.' 'Raum5-Konfiguration ist importiert (r5_pauto vorhanden)' }
  else { Zeile FEHLER 'Companion-Konfig.' 'Variable r5_pauto fehlt' 'Import / Export -> Raum5_Companion.companionconfig importieren' }
  $scene = Get-Var 'variable/obs/scene_active'
  if ($scene) { Zeile OK 'OBS' ('verbunden, aktive Szene: ' + $scene) }
  else { Zeile FEHLER 'OBS' 'keine Verbindung von Companion zu OBS' 'OBS starten; Companion -> Connections -> obs: Passwort/Port 4455 pruefen' }
  $live = Get-Var 'custom-variable/r5_live'; $room = Get-Var 'custom-variable/r5_room'
  Zeile INFO 'Raum-Status' ('Raum ' + $(if ($room -eq '1') { 'an' } else { 'aus' }) + ', Virtual Cam ' + $(if ($live -eq '1') { 'laeuft' } else { 'aus' }))
}
$ccfg = Join-Path $env:APPDATA 'companion\config.json'
if (Test-Path $ccfg) {
  try {
    $bind = (Get-Content -Raw $ccfg | ConvertFrom-Json).bind_ip
    if ($bind -eq '127.0.0.1') { Zeile WARN 'Companion-Netzwerk' 'hoert nur auf 127.0.0.1 - Tablet kann keine Befehle senden' 'Companion-Fenster: GUI Interface -> "All Interfaces: IPv4 Only"' }
    else { Zeile OK 'Companion-Netzwerk' ('hoert auf ' + $bind) }
  } catch { }
}

# ---------- RM-CR ----------
$ping = $false
try { $ping = (New-Object System.Net.NetworkInformation.Ping).Send($rmcrIp, 1000).Status -eq 'Success' } catch { }
$tcp = New-Object System.Net.Sockets.TcpClient
$verbunden = $false
try { $ar = $tcp.BeginConnect($rmcrIp, $rmcrPort, $null, $null); $verbunden = $ar.AsyncWaitHandle.WaitOne(2000) -and $tcp.Connected } catch { }
if ($verbunden) {
  Zeile OK 'RM-CR' ('{0}:{1} erreichbar (RCP)' -f $rmcrIp, $rmcrPort)
  # 2 s Meter lesen: welche Kanaele haben Signal?
  try {
    $s = $tcp.GetStream(); $w = New-Object System.IO.StreamWriter($s); $w.NewLine = "`n"; $w.AutoFlush = $true
    $meter = if ($cfg) { $cfg.meter } else { 'RM:NeInPostFader' }
    $w.WriteLine("mtrstart $meter 100")
    $buf = New-Object byte[] 8192; $text = ''; $max = @{}; $ende = (Get-Date).AddSeconds(2)
    while ((Get-Date) -lt $ende) {
      while ($s.DataAvailable) { $n = $s.Read($buf, 0, $buf.Length); $text += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n) }
      Start-Sleep -Milliseconds 50
    }
    foreach ($line in ($text -split "`n")) {
      $i = $line.IndexOf(' level '); if ($line -notlike 'NOTIFY mtr *' -or $i -lt 0) { continue }
      $hex = $line.Substring($i + 7) -replace '[^0-9A-Fa-f]', ''
      for ($k = 0; $k -lt [Math]::Floor($hex.Length / 2); $k++) { $v = [Convert]::ToInt32($hex.Substring($k * 2, 2), 16); if (-not $max.ContainsKey($k + 1) -or $v -gt $max[$k + 1]) { $max[$k + 1] = $v } }
    }
    if ($max.Count -eq 0) { Zeile WARN 'Mikrofon-Pegel' 'RM-CR liefert keine Meter-Daten' 'Firmware/Meter-Name pruefen (mikro-automatik.json "meter")' }
    else {
      $aktiv = @($max.Keys | Where-Object { $max[$_] -gt 0x20 } | Sort-Object)
      if ($aktiv.Count -eq 0) { Zeile WARN 'Mikrofon-Pegel' 'alle Kanaele still' 'RM-TT im RM-CR registriert (Settings -> Peripheral)? Mikrofone stumm?' }
      else { Zeile OK 'Mikrofon-Pegel' ('Signal auf Kanal ' + (($aktiv | ForEach-Object { '{0} ({1:X2})' -f $_, $max[$_] }) -join ', ')) }
      if ($cfg) {
        $zu = @(); foreach ($p in $cfg.mikrofone.PSObject.Properties) { if (@($p.Value).Count) { $zu += ('Mikro {0}=Kanal {1}' -f $p.Name, (@($p.Value) -join '+')) } }
        Zeile INFO 'Zuordnung (json)' ($zu -join ', ')
      }
    }
  } catch { Zeile WARN 'Mikrofon-Pegel' ('Lesen fehlgeschlagen: ' + $_.Exception.Message) }
} elseif ($ping) { Zeile FEHLER 'RM-CR' ('{0} antwortet auf Ping, aber Port {1} ist zu' -f $rmcrIp, $rmcrPort) 'RM-CR neu starten; IP in mikro-automatik.json und Companion "rmcr" pruefen' }
else { Zeile FEHLER 'RM-CR' ($rmcrIp + ' nicht erreichbar') 'Netzwerkkabel zum RM-CR? IP mit "RM Device Finder" pruefen' }
$tcp.Close()

# ---------- Webserver / Automatik ----------
$web = Get-Http 'http://127.0.0.1:8080/'
if ($web -and $web.Code -eq 200 -and $web.Text -match 'Sitzungszimmer 5') { Zeile OK 'Webserver' 'Tablet-Seite auf Port 8080 erreichbar' }
else { Zeile FEHLER 'Webserver' 'Port 8080 antwortet nicht' 'installieren.ps1 als Administrator ausfuehren oder PC neu starten' }
$log = Join-Path $PSScriptRoot 'mikro-automatik.log'
if (Test-Path $log) {
  $zeilen = @(Get-Content $log -Tail 200 -Encoding UTF8)
  $start = $zeilen | Where-Object { $_ -match '  Start ' } | Select-Object -Last 1
  $fehl = $zeilen | Where-Object { $_ -match 'Fehler|nicht erreichbar' } | Select-Object -Last 1
  $alter = (New-TimeSpan -Start (Get-Item $log).LastWriteTime -End (Get-Date)).TotalMinutes
  $txt = if ($start) { 'gestartet ' + $start.Substring(0, 19) } else { 'laeuft' }
  if ($fehl -and $zeilen.IndexOf($fehl) -gt $zeilen.IndexOf($start)) { Zeile WARN 'Mikrofon-Automatik' ($txt + ', letzte Meldung: ' + $fehl.Substring(21)) 'Protokoll C:\Raumsteuerung\mikro-automatik.log ansehen' }
  else { Zeile OK 'Mikrofon-Automatik' ($txt + ', Protokoll zuletzt vor ' + [int]$alter + ' min') }
} else { Zeile WARN 'Mikrofon-Automatik' 'kein Protokoll gefunden' 'Aufgabe "Raumsteuerung Mikrofon-Automatik" laeuft nicht? installieren.ps1 ausfuehren' }
$auto = if ($c) { Get-Var 'custom-variable/r5_pauto' } else { $null }
if ($auto) { Zeile INFO 'Publikum-Automatik' $(if ($auto -eq '1') { 'an (Tablet-Schalter)' } else { 'aus (Tablet-Schalter)' }) }

$tlog = Join-Path $PSScriptRoot 'teams-steuerung.log'
if (Test-Path $tlog) {
  $tz = @(Get-Content $tlog -Tail 50 -Encoding UTF8)
  $tstart = $tz | Where-Object { $_ -match 'Start Teams-Steuerung' } | Select-Object -Last 1
  $tin = if ($c) { Get-Var 'custom-variable/r5_t_in' } else { $null }
  $txt = $(if ($tstart) { 'gestartet ' + $tstart.Substring(0, 19) } else { 'laeuft' }) + $(if ($tin -eq '1') { ', Teams-Meeting offen' } else { ', kein Meeting' })
  Zeile OK 'Teams-Steuerung' $txt
} else { Zeile WARN 'Teams-Steuerung' 'kein Protokoll - Tablet kann Teams nicht bedienen' 'installieren.ps1 ausfuehren und Benutzer ab-/anmelden (Aufgabe startet bei Anmeldung)' }

# ---------- Netzwerk / Firewall ----------
$netz = @{}
try { foreach ($p in Get-NetConnectionProfile) { $netz[$p.InterfaceAlias] = [string]$p.NetworkCategory } } catch { }
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
foreach ($i in $ips) {
  $kat = $netz[$i.InterfaceAlias]
  $dhcp = if ($i.PrefixOrigin -eq 'Dhcp') { 'DHCP' } else { 'fest' }
  $t = ('http://{0}:8080   {1}, {2}' -f $i.IPAddress, $i.InterfaceAlias, $dhcp)
  if ($kat -eq 'Public') { Zeile WARN 'Tablet-Adresse' ($t + ', Netz "Oeffentlich"') 'Firewall-Regeln gelten nur fuer Privat/Domaene: Einstellungen -> Netzwerk -> Netzwerkprofiltyp "Privat"' }
  elseif ($kat) { Zeile OK 'Tablet-Adresse' ($t + ', Netz ' + $kat) }
  else { Zeile INFO 'Tablet-Adresse' ($t + ', nicht verbunden/ohne Profil') }
}
$regeln = @(Get-NetFirewallRule -DisplayName 'Raumsteuerung Port *' -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' })
if ($regeln.Count -ge 2) { Zeile OK 'Firewall' 'Regeln fuer Port 8080 und 8000 vorhanden' }
else { Zeile FEHLER 'Firewall' 'Regeln "Raumsteuerung Port 8080/8000" fehlen' 'installieren.ps1 als Administrator ausfuehren' }

# ---------- Audio ----------
$audio = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match 'Yamaha|RM-CR|RM-' })
if ($audio.Count) { Zeile OK 'Audio (USB)' (($audio | ForEach-Object FriendlyName) -join '; ') }
else { Zeile WARN 'Audio (USB)' 'kein RM-CR-Audiogeraet gefunden' 'RM-CR per USB anschliessen und in Windows/Teams als Lautsprecher + Mikrofon waehlen' }

Write-Host ''
if ($script:fehler) { Write-Host ('{0} Fehler, {1} Hinweise.' -f $script:fehler, $script:warn) -ForegroundColor Red }
elseif ($script:warn) { Write-Host ('Keine Fehler, {0} Hinweise.' -f $script:warn) -ForegroundColor Yellow }
else { Write-Host 'Alles in Ordnung.' -ForegroundColor Green }
