@echo off
setlocal
title PhotoCraft GPU fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Verify %*
echo.
pause
