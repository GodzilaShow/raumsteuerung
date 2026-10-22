# Einmalig auf dem Raum-PC als Administrator ausfuehren:
# Rechtsklick -> "Mit PowerShell ausfuehren" (oder in Admin-PowerShell: .\installieren.ps1)
$ErrorActionPreference = 'Stop'
# Ohne Administratorrechte neu starten (sonst scheitern Firewall und Aufgabenplanung)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}
$ziel = 'C:\Raumsteuerung'
New-Item -ItemType Directory -Force -Path $ziel | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $ziel -Force -Exclude 'installieren.ps1','deinstallieren.ps1','mikro-automatik.json','*.log'
# Mikrofon-Einstellungen nur beim ersten Mal kopieren (spaeter angepasste Werte nicht ueberschreiben)
if (-not (Test-Path (Join-Path $ziel 'mikro-automatik.json'))) { Copy-Item (Join-Path $PSScriptRoot 'mikro-automatik.json') $ziel }
# Firewall: Port 8080 (Seite) und 8000 (Companion) im lokalen Netz erlauben
foreach ($p in 8080, 8000) {
  $n = "Raumsteuerung Port $p"
  if (-not (Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $n -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Domain,Private | Out-Null
  }
}
# Aufgabe: Webserver startet bei jedem Systemstart (auch ohne Anmeldung)
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ziel\server.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
# Auch im Akkubetrieb starten und weiterlaufen (Standard waere: beim Ziehen des Netzsteckers beenden)
$set     = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Raumsteuerung Webserver' -Action $action -Trigger $trigger -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'Raumsteuerung Webserver'
# Aufgabe: Mikrofon-Automatik (Publikum-Kamera folgt dem Tischmikrofon), Einstellungen in mikro-automatik.json
$action2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ziel\mikro-automatik.ps1`""
Register-ScheduledTask -TaskName 'Raumsteuerung Mikrofon-Automatik' -Action $action2 -Trigger $trigger -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Stop-ScheduledTask -TaskName 'Raumsteuerung Mikrofon-Automatik' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'Raumsteuerung Mikrofon-Automatik'
# Aufgabe: Teams-Steuerung (Tablet -> Mikro/Bild/Verlassen). Braucht den Desktop des angemeldeten Benutzers
# (UI Automation), deshalb "bei Anmeldung" fuer alle Benutzer statt SYSTEM. Raum-PC: automatische Anmeldung.
# Ohne sichtbares Fenster: Windows 11 oeffnet PowerShell im Windows Terminal, das -WindowStyle Hidden ignoriert
# (Fenster unten in der Taskleiste - wer es schliesst, beendet die Teams-Steuerung). conhost --headless startet
# die Konsole unsichtbar (ab Windows 10 1809); aeltere Systeme wie bisher.
$ps3 = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ziel\teams-steuerung.ps1`""
if ([Environment]::OSVersion.Version.Build -ge 17763) {
  $action3 = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument "--headless powershell.exe $ps3"
} else {
  $action3 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $ps3
}
$trigger3 = New-ScheduledTaskTrigger -AtLogOn
$princ3   = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited   # Gruppe "Benutzer"
Register-ScheduledTask -TaskName 'Raumsteuerung Teams-Steuerung' -Action $action3 -Trigger $trigger3 -Settings $set -Principal $princ3 -Force | Out-Null
# Laeuft schon eine (sichtbare) Teams-Steuerung, beenden und unsichtbar neu starten
$alt3 = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'teams-steuerung\.ps1' -and $_.CommandLine -notmatch '-Status|-Befehl' }
if ($alt3) { $alt3 | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep 1 }
Start-ScheduledTask -TaskName 'Raumsteuerung Teams-Steuerung' -ErrorAction SilentlyContinue
# Alle Netzwerkadressen anzeigen – das Tablet braucht die Adresse aus SEINEM Netz (z. B. AV-WLAN)
$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
Write-Host ""
Write-Host "Fertig. Auf dem Tablet eine dieser Adressen oeffnen (die aus dem Tablet-Netz):" -ForegroundColor Green
foreach ($i in $ips) { Write-Host ("   http://{0}:8080    ({1})" -f $i.IPAddress, $i.InterfaceAlias) -ForegroundColor Green }
Read-Host "Enter druecken zum Schliessen"
