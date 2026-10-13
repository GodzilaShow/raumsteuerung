# Entfernt Webserver-Aufgabe und Firewall-Regeln (als Administrator ausfuehren)
Unregister-ScheduledTask -TaskName 'Raumsteuerung Webserver' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Raumsteuerung Mikrofon-Automatik' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Raumsteuerung Teams-Steuerung' -Confirm:$false -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName 'Raumsteuerung Port *' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "Entfernt. Der Ordner C:\Raumsteuerung kann geloescht werden."
