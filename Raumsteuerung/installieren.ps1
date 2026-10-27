# Einmalig auf dem Raum-PC als Administrator ausfuehren:
# Rechtsklick -> "Mit PowerShell ausfuehren" (oder in Admin-PowerShell: .\installieren.ps1)
# Kopiert alles nach C:\Raumsteuerung, oeffnet die Firewall und startet Raumsteuerung.exe bei jeder Anmeldung.
# Das Programm (Symbol im Infobereich) startet Webserver und Teams-Steuerung unsichtbar -
# die frueheren Aufgaben in der Aufgabenplanung werden entfernt.
# -OhneWarten: am Ende nicht auf Enter warten (fuer automatisches Aktualisieren, z. B. durch Claude Code)
param([switch]$OhneWarten)
$ErrorActionPreference = 'Stop'
# Ohne Administratorrechte neu starten (sonst scheitern Firewall und Autostart fuer alle Benutzer)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" + $(if ($OhneWarten) { ' -OhneWarten' } else { '' }))
  exit
}
$ziel = 'C:\Raumsteuerung'
$exe  = Join-Path $ziel 'Raumsteuerung.exe'

# Laufendes Programm beenden (sonst ist Raumsteuerung.exe gesperrt); seine Dienste enden mit
Get-Process -Name Raumsteuerung -ErrorAction SilentlyContinue | Stop-Process -Force
# Fruehere Aufgaben (bis 22.10.2026) entfernen und ihre Skripte beenden
foreach ($t in 'Raumsteuerung Webserver', 'Raumsteuerung Mikrofon-Automatik', 'Raumsteuerung Teams-Steuerung') {
  if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $t -Confirm:$false
    Write-Host "Aufgabe entfernt: $t"
  }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match '(server|mikro-automatik|teams-steuerung)\.ps1' -and $_.CommandLine -notmatch '-Status|-Befehl|-Zuordnung' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

New-Item -ItemType Directory -Force -Path $ziel | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $ziel -Force -Exclude 'installieren.ps1','deinstallieren.ps1','mikro-automatik.json','pause.png','*.log'
# Einstellungen nur beim ersten Mal kopieren (spaeter angepasste Werte nicht ueberschreiben; Name bleibt aus Kompatibilitaet)
if (-not (Test-Path (Join-Path $ziel 'mikro-automatik.json'))) { Copy-Item (Join-Path $PSScriptRoot 'mikro-automatik.json') $ziel }
# Pausenbild ebenso: ein eigenes pause.png in C:\Raumsteuerung bleibt erhalten.
# Alte Standardbilder (weiß mit Text; erste dunkle Fassung vom 27.10.2026) werden durch das aktuelle ersetzt.
$pauseZiel = Join-Path $ziel 'pause.png'
$altePausenbilder = @('57FB1E577966B125EB9B9C14CBF0351E7724CB01115446A252C7644372F6AE04', 'E9F0CECBC1BC42F2EA937CC3B35AA822B41B5302C6BCFDBF7FFF638FA79BE792')
if (-not (Test-Path $pauseZiel) -or $altePausenbilder -contains (Get-FileHash $pauseZiel -Algorithm SHA256).Hash) {
  Copy-Item (Join-Path $PSScriptRoot 'pause.png') $pauseZiel -Force
}
# Nicht mehr benutzt (Publikum-Kamera fest, keine Mikrofon-Automatik seit 22.10.2026)
foreach ($alt in 'mikro-automatik.ps1', 'mikrofone-testen.cmd') { Remove-Item (Join-Path $ziel $alt) -Force -ErrorAction SilentlyContinue }

# Firewall: Port 8080 (Seite) und 8000 (Companion) im lokalen Netz erlauben
foreach ($p in 8080, 8000) {
  $n = "Raumsteuerung Port $p"
  if (-not (Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $n -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Domain,Private | Out-Null
  }
}

# Autostart fuer alle Benutzer bei der Anmeldung (Raum-PC: automatische Anmeldung des Raumkontos)
Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Raumsteuerung' -Value "`"$exe`" --tray"
# Jetzt starten - ueber den Explorer, damit es als normaler Benutzer laeuft (nicht als Administrator)
Start-Process explorer.exe -ArgumentList "`"$exe`""

# Alle Netzwerkadressen anzeigen – das Tablet braucht die Adresse aus SEINEM Netz (z. B. AV-WLAN)
$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
Write-Host ""
Write-Host "Fertig. Raumsteuerung laeuft (Symbol im Infobereich unten rechts)." -ForegroundColor Green
Write-Host "Auf dem Tablet eine dieser Adressen oeffnen (die aus dem Tablet-Netz):" -ForegroundColor Green
foreach ($i in $ips) { Write-Host ("   http://{0}:8080    ({1})" -f $i.IPAddress, $i.InterfaceAlias) -ForegroundColor Green }
if (-not $OhneWarten) { Read-Host "Enter druecken zum Schliessen" }
