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
wsl -e bash -c "cd /home/zachk/sam-3d-objects && /home/zachk/miniconda3/envs/sam3d-objects/bin/python server.py"
pause
