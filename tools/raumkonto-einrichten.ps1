# Raumkonto "Sitzungszimmer5" auf dem Raum-PC anlegen und fuer oeffentliche Nutzung einschraenken.
# Als Administrator ausfuehren. Zwei Durchgaenge:
#
#   1) .\raumkonto-einrichten.ps1
#        -> legt den lokalen Benutzer an (Passwort wird abgefragt, nicht gespeichert)
#        -> Rechner-Einstellungen: kein Energiesparen, kein Sperrbildschirm, Edge speichert keine Passwoerter
#      Danach EINMAL als Sitzungszimmer5 anmelden (Teams-Anmeldung, Geraete waehlen), wieder abmelden.
#
#   2) .\raumkonto-einrichten.ps1 -Einschraenken -VonBenutzer <bisheriger Benutzer>
#        -> kopiert Companion- und OBS-Einstellungen vom bisherigen Benutzer
#        -> sperrt fuer das Raumkonto: Systemsteuerung/Einstellungen, Ausfuehren, Task-Manager, Regedit,
#           Eingabeaufforderung (Skripte wie pruefen.cmd laufen weiter), Sperren, Passwort aendern
#
# Rueckgaengig: .\raumkonto-einrichten.ps1 -Aufheben  (nimmt die Sperren des Raumkontos wieder weg)

param(
  [switch]$Einschraenken,
  [switch]$Aufheben,
  [string]$VonBenutzer = '',
  [string]$Name = 'Sitzungszimmer5'
)
$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Bitte als Administrator starten.' -ForegroundColor Red; exit 1 }

function Profilpfad([string]$benutzer) {
  $sid = (New-Object Security.Principal.NTAccount($benutzer)).Translate([Security.Principal.SecurityIdentifier]).Value
  $p = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
  return @{ Sid = $sid; Pfad = $p }
}

# Sperren im Benutzerzweig des Raumkontos (Wert 1 = gesperrt, $null = entfernen)
$sperren = @(
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoControlPanel';      Wert = 1 },
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'NoRun';               Wert = 1 },
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\System';   Name = 'DisableTaskMgr';      Wert = 1 },
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\System';   Name = 'DisableRegistryTools';Wert = 1 },
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\System';   Name = 'DisableChangePassword';Wert = 1 },
  @{ Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\System';   Name = 'DisableLockWorkstation';Wert = 1 },
  # 2 = Eingabeaufforderung gesperrt, Batchdateien (pruefen.cmd) laufen weiter. PowerShell bleibt erlaubt
  # (teams-steuerung.ps1 und server.ps1 laufen als dieser Benutzer).
  @{ Key = 'Software\Policies\Microsoft\Windows\System';                  Name = 'DisableCMD';          Wert = 2 }
)

function Benutzerzweig([scriptblock]$tun) {
  $info = Profilpfad $Name
  if (-not $info.Pfad -or -not (Test-Path (Join-Path $info.Pfad 'NTUSER.DAT'))) {
    Write-Host "Profil von $Name fehlt. Erst einmal als $Name anmelden und wieder abmelden." -ForegroundColor Red; exit 1
  }
  $geladen = Test-Path "Registry::HKEY_USERS\$($info.Sid)"
  $wurzel = if ($geladen) { "Registry::HKEY_USERS\$($info.Sid)" } else { 'Registry::HKEY_USERS\R5Raumkonto' }
  if (-not $geladen) { & reg.exe load 'HKU\R5Raumkonto' (Join-Path $info.Pfad 'NTUSER.DAT') | Out-Null }
  try { & $tun $wurzel $info.Pfad }
  finally {
    if (-not $geladen) { [gc]::Collect(); Start-Sleep -Milliseconds 500; & reg.exe unload 'HKU\R5Raumkonto' | Out-Null }
  }
}

if ($Aufheben) {
  Benutzerzweig {
    param($wurzel, $pfad)
    foreach ($s in $sperren) { Remove-ItemProperty -Path "$wurzel\$($s.Key)" -Name $s.Name -ErrorAction SilentlyContinue }
  }
  Write-Host "Sperren fuer $Name aufgehoben (wirkt nach der naechsten Anmeldung)." -ForegroundColor Green
  exit 0
}

if (-not $Einschraenken) {
  # ---------------- Durchgang 1: Benutzer + Rechner-Einstellungen
  if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) {
    Write-Host "Benutzer $Name gibt es schon - wird nicht neu angelegt." -ForegroundColor Yellow
  } else {
    $pw = Read-Host "Passwort fuer $Name" -AsSecureString
    New-LocalUser -Name $Name -FullName 'Sitzungszimmer 5' -Description 'Raumkonto Sitzungszimmer 5 (Raum-PC, Teams)' `
      -Password $pw -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Add-LocalGroupMember -Group (Get-LocalGroup -SID 'S-1-5-32-545').Name -Member $Name   # "Benutzer", keine Adminrechte
    Write-Host "Benutzer $Name angelegt (Standardbenutzer, Passwort laeuft nie ab)." -ForegroundColor Green
  }

  # Kein Energiesparen / Bildschirm-aus am Netzteil (Displays steuert die Raumsteuerung)
  & powercfg.exe /change standby-timeout-ac 0
  & powercfg.exe /change monitor-timeout-ac 0
  & powercfg.exe /change hibernate-timeout-ac 0
  # Kein Sperrbildschirm
  New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Force | Out-Null
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1 -Type DWord
  # Edge: keine Passwoerter speichern (oeffentlicher PC)
  New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Force | Out-Null
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'PasswordManagerEnabled' -Value 0 -Type DWord

  Write-Host ''
  Write-Host 'Weiter:' -ForegroundColor Cyan
  Write-Host "  1. Abmelden, als $Name anmelden. Teams mit dem Raumkonto (M365) anmelden,"
  Write-Host '     Geraete: Mikrofon/Lautsprecher = Yamaha RM-CR, Kamera = OBS Virtual Camera.'
  Write-Host '  2. Wieder abmelden, als Administrator anmelden und ausfuehren:'
  Write-Host "     .\raumkonto-einrichten.ps1 -Einschraenken -VonBenutzer <bisheriger Benutzer>"
  exit 0
}

# ---------------- Durchgang 2: Einstellungen kopieren + Sperren
if (Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$Name" }) {
  Write-Host "$Name ist noch angemeldet. Bitte erst abmelden." -ForegroundColor Red; exit 1
}

if ($VonBenutzer -and (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*companion*' -or $_.ProcessName -like 'obs64' })) {
  Write-Host 'Companion oder OBS laeuft noch - bitte zuerst beenden (sonst wird eine halbfertige Datenbank kopiert).' -ForegroundColor Red; exit 1
}

Benutzerzweig {
  param($wurzel, $pfad)
  if ($VonBenutzer) {
    $quelle = (Profilpfad $VonBenutzer).Pfad
    foreach ($ordner in 'companion', 'obs-studio') {
      $von = Join-Path $quelle "AppData\Roaming\$ordner"
      $nach = Join-Path $pfad "AppData\Roaming\$ordner"
      if (Test-Path $von) {
        if (Test-Path $nach) { Rename-Item $nach "$ordner.vorher-$(Get-Date -Format yyyyMMdd-HHmmss)" }
        Copy-Item $von $nach -Recurse
        Write-Host "Kopiert: $ordner" -ForegroundColor Green
      } else { Write-Host "Nicht gefunden bei $VonBenutzer : $ordner" -ForegroundColor Yellow }
    }
    & icacls.exe (Join-Path $pfad 'AppData\Roaming') /grant "${Name}:(OI)(CI)F" /T /C /Q | Out-Null
  }
  foreach ($s in $sperren) {
    New-Item -Path "$wurzel\$($s.Key)" -Force | Out-Null
    Set-ItemProperty -Path "$wurzel\$($s.Key)" -Name $s.Name -Value $s.Wert -Type DWord
  }
}
Write-Host "Sperren fuer $Name gesetzt. Rueckgaengig: -Aufheben" -ForegroundColor Green
Write-Host 'Letzter Schritt: automatische Anmeldung mit Sysinternals Autologon (Passwort dort selbst eingeben).' -ForegroundColor Cyan
