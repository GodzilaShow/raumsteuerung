# Baut Raumsteuerung\Raumsteuerung.exe unter Windows mit dem C#-Compiler von .NET Framework 4.x (in Windows enthalten,
# kann C# 5 - der Code bleibt deshalb bei C# 5). Gleiche Parameter wie build.sh (Linux/Mono).
# Aufruf: powershell -NoProfile -ExecutionPolicy Bypass -File tools\RaumsteuerungTray\build.ps1
$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw "csc.exe nicht gefunden ($csc)" }
Push-Location $PSScriptRoot
try {
  $ziel = Resolve-Path '..\..\Raumsteuerung' | Join-Path -ChildPath 'Raumsteuerung.exe'
  $quellen = @(Get-ChildItem *.cs | ForEach-Object { $_.Name })
  & $csc /nologo /target:winexe /platform:anycpu /optimize+ /win32icon:app.ico /win32manifest:app.manifest `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Management.dll /r:System.Web.Extensions.dll `
    "/out:$ziel" @quellen
  if ($LASTEXITCODE -ne 0) { throw "Bauen fehlgeschlagen (csc Code $LASTEXITCODE)" }
  Get-Item $ziel | Select-Object FullName, Length, LastWriteTime
} finally { Pop-Location }
