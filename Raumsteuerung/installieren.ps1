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
Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $ziel -Force -Exclude 'installieren.ps1','deinstallieren.ps1'
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
$set     = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'Raumsteuerung Webserver' -Action $action -Trigger $trigger -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'Raumsteuerung Webserver'
# Alle Netzwerkadressen anzeigen – das Tablet braucht die Adresse aus SEINEM Netz (z. B. AV-WLAN)
$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' }
Write-Host ""
Write-Host "Fertig. Auf dem Tablet eine dieser Adressen oeffnen (die aus dem Tablet-Netz):" -ForegroundColor Green
foreach ($i in $ips) { Write-Host ("   http://{0}:8080    ({1})" -f $i.IPAddress, $i.InterfaceAlias) -ForegroundColor Green }
Read-Host "Enter druecken zum Schliessen"
