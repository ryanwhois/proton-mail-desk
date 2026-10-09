@echo off
setlocal
set "PROJECT_ROOT=%~dp0"

if not exist "%PROJECT_ROOT%node_modules\proton-mail-bridge-client\dist\cli.js" (
  echo Proton Mail Desk needs its local dependencies installed first.
  echo Open this folder in PowerShell and run: npm.cmd ci
  pause
  exit /b 1
)

pushd "%PROJECT_ROOT%"
pwsh.exe -NoLogo -NoProfile -File "%PROJECT_ROOT%scripts\Start-ProtonMailDesk.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
popd

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Proton Mail Desk exited with code %EXIT_CODE%.
  pause
)

exit /b %EXIT_CODE%
