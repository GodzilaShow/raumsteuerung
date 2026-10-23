#!/usr/bin/env bash
# Baut Raumsteuerung/Raumsteuerung.exe (.NET Framework 4.8, in Windows 10/11 enthalten) - unter Linux mit Mono (mcs),
# unter Windows mit build.ps1 (csc.exe aus .NET Framework 4.x, nur C# 5 -> Code bei C# 5 halten).
set -euo pipefail
cd "$(dirname "$0")"
mcs -target:winexe -platform:anycpu -optimize+ -langversion:5 -sdk:4.5 \
  -win32icon:app.ico -win32manifest:app.manifest \
  -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:System.Management.dll -r:System.Web.Extensions.dll \
  -out:../../Raumsteuerung/Raumsteuerung.exe *.cs
ls -la ../../Raumsteuerung/Raumsteuerung.exe
