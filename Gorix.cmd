@echo off
rem Gorix'i baslatir (Gorix.vbs calismazsa bunu kullan)
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Gorix.ps1"
