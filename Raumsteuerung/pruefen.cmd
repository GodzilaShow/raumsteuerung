@echo off
rem Schnellpruefung der Raumsteuerung (Companion, OBS, RM-CR, Webserver, Netzwerk). Aendert nichts.
mode con: cols=110 lines=45
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pruefen.ps1"
pause
