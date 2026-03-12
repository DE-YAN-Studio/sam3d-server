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
wsl -e bash -ic "source ~/miniconda3/etc/profile.d/conda.sh && conda activate sam3d-objects && cd ~/sam-3d-objects && python server.py"
pause
