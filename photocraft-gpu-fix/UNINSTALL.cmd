@echo off
setlocal
title PhotoCraft GPU fix - undo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
