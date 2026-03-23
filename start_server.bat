@echo off
title SAM3D Server
echo.
echo  Starting SAM3D server...
echo  Server will be available at http://localhost:8766
echo  API docs:    http://localhost:8766/docs
echo  Health:      http://localhost:8766/health
echo.
echo  Press Ctrl+C to stop.
echo.

set REPO_DIR=%~dp0
set REPO_DIR_NOSLASH=%REPO_DIR:~0,-1%
for /f "delims=" %%i in ('wsl wslpath "%REPO_DIR_NOSLASH%"') do set WSL_REPO_DIR=%%i
set WSL_REPO_DIR=%WSL_REPO_DIR%/

wsl -- bash "%WSL_REPO_DIR%start_server.sh"
pause
