# Raum 5 – Einrichtung auf diesem PC (einmalig, als Administrator)
# Rechtsklick -> "Mit PowerShell ausfuehren". Fragt nach Admin-Rechten.
$ErrorActionPreference = 'Stop'
$repo   = 'https://github.com/godzilashow/raumsteuerung'
$branch = 'claude/modest-mayer-tbnbre'
$ziel   = 'C:\Raum5'

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}
function Schritt($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function PfadNeu { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function WingetInstall($id) {
  winget list --id $id -e --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host "$id ist schon installiert."; return }
  winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { Write-Host "$id konnte nicht installiert werden (Code $LASTEXITCODE) - bitte von Hand installieren." -ForegroundColor Yellow }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "winget fehlt (Microsoft Store -> 'App Installer' installieren)." -ForegroundColor Red
  Read-Host "Enter"; exit 1
}

Schritt "1/5 Git"
# Git installiert, aber nicht im PATH (passiert nach manchen Installationen) -> dauerhaft fuer alle Benutzer eintragen
function GitPfad {
  foreach ($d in "$env:ProgramFiles\Git\cmd", "${env:ProgramFiles(x86)}\Git\cmd", "$env:LOCALAPPDATA\Programs\Git\cmd") {
    if (-not (Test-Path (Join-Path $d 'git.exe'))) { continue }
    $p = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($p -split ';') -notcontains $d) { [Environment]::SetEnvironmentVariable('Path', "$p;$d", 'Machine'); Write-Host "Git in den PATH eingetragen: $d" }
    PfadNeu; return
  }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { GitPfad }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { WingetInstall 'Git.Git'; PfadNeu; GitPfad }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "Git nicht gefunden - PowerShell neu oeffnen und Skript nochmal starten." -ForegroundColor Red; Read-Host "Enter"; exit 1 }

Schritt "2/5 Repository nach $ziel (Branch $branch)"
if (Test-Path (Join-Path $ziel '.git')) {
  git -C $ziel fetch origin $branch
  git -C $ziel checkout $branch
  git -C $ziel pull --ff-only origin $branch
} elseif (Test-Path $ziel) {
  Write-Host "$ziel existiert, ist aber kein Git-Ordner - bitte umbenennen und neu starten." -ForegroundColor Red; Read-Host "Enter"; exit 1
} else {
  git clone -b $branch $repo $ziel
}
if ($LASTEXITCODE -ne 0) { Write-Host "Git-Fehler." -ForegroundColor Red; Read-Host "Enter"; exit 1 }
git -C $ziel log --oneline -1

Schritt "3/5 OBS Studio"
WingetInstall 'OBSProject.OBSStudio'

Schritt "4/5 Bitfocus Companion"
WingetInstall 'Bitfocus.Companion'

Schritt "5/5 Raumsteuerung installieren (C:\Raumsteuerung, Webserver, Mikrofon-Automatik, Teams-Steuerung, Firewall 8080/8000)"
& (Join-Path $ziel 'Raumsteuerung\installieren.ps1')

Write-Host ""
Write-Host "Fertig. Jetzt von Hand (ANLEITUNG.txt Abschnitt 2, 3, 10):" -ForegroundColor Green
Write-Host " - OBS: Szenensammlung -> Importieren -> $ziel\Raum5_OBS_Szenen_Backup.json; WebSocket an, Port 4455, Passwort"
Write-Host " - Companion: http://127.0.0.1:8000 -> erst Export sichern, dann $ziel\Raum5_Companion.companionconfig importieren"
Write-Host "   obs-Passwort eintragen, rmcr-IP pruefen, 'Run at login', Admin-Passwort"
Write-Host " - Netzwerkprofil 'Privat', danach C:\Raumsteuerung\pruefen.cmd"
Write-Host " - Raumsteuerung laeuft jetzt im Infobereich (Symbol unten rechts) - dort Status und Einstellungen"
Read-Host "Enter druecken zum Schliessen"
