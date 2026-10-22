#!/usr/bin/env bash
# Baut Raumsteuerung/Raumsteuerung.exe (.NET Framework 4.8, in Windows 10/11 enthalten) - unter Linux mit Mono (mcs),
# unter Windows mit csc.exe aus C:\Windows\Microsoft.NET\Framework64\v4.0.30319 (gleiche Parameter).
set -euo pipefail
cd "$(dirname "$0")"
mcs -target:winexe -platform:anycpu -optimize+ -langversion:7 -sdk:4.5 \
  -win32icon:app.ico -win32manifest:app.manifest \
  -r:System.Windows.Forms.dll -r:System.Drawing.dll -r:System.Management.dll -r:System.Web.Extensions.dll \
  -out:../../Raumsteuerung/Raumsteuerung.exe *.cs
ls -la ../../Raumsteuerung/Raumsteuerung.exe
