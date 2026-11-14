@echo off
cd /d "%~dp0"
"%~dp0rojo.exe" serve "%~dp0default.project.json" %*
