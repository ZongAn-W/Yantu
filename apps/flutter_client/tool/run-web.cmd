@echo off
setlocal
powershell.exe -NoLogo -NoProfile -File "%~dp0run-web.ps1" %*
exit /b %errorlevel%
