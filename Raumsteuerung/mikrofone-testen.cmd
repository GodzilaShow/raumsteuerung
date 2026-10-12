@echo off
rem Pegel aller RM-CR-Kanaele live anzeigen: nacheinander in jedes Tischmikrofon sprechen.
mode con: cols=90 lines=32
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mikro-automatik.ps1" -Zuordnung
pause
