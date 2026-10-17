@echo off
setlocal
powershell.exe -NoLogo -NoProfile -File "%~dp0build-release.ps1" %*
exit /b %errorlevel%
