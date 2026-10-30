@echo off
setlocal
set "FIXDIR=%~dp0"
set "WGPU_DX12_COMPILER=dxc"
set "PATH=%FIXDIR%bin;%PATH%"
set "EXE=%ProgramFiles%\Photocraft\photocraft.exe"
if not exist "%EXE%" set "EXE=%LOCALAPPDATA%\Programs\Photocraft\photocraft.exe"
if not exist "%EXE%" (
  echo PhotoCraft not found in Program Files or LocalAppData.
  echo Run INSTALL.cmd "D:\path\to\Photocraft" to tell it where PhotoCraft is.
  pause
  exit /b 1
)
start "" "%EXE%" %*
