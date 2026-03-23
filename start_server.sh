#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate sam3d-objects
cd ~/sam-3d-objects
echo "Starting SAM3D server on http://localhost:8766"
echo "Health: http://localhost:8766/health"
echo ""
python -u server.py
