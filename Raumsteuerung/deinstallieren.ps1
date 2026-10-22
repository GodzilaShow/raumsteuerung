# Entfernt Raumsteuerung (Programm, Autostart, fruehere Aufgaben) und die Firewall-Regeln (als Administrator ausfuehren)
Get-Process -Name Raumsteuerung -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Raumsteuerung' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Raumsteuerung' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Raumsteuerung Webserver' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Raumsteuerung Mikrofon-Automatik' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Raumsteuerung Teams-Steuerung' -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName 'Raumsteuerung Port *' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "Entfernt. Der Ordner C:\Raumsteuerung kann geloescht werden."
