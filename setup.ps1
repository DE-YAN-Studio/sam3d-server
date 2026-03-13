<#
.SYNOPSIS
    Full one-shot setup for SAM3D on Windows with WSL2 + Ubuntu.

.DESCRIPTION
    Idempotent — safe to re-run at any step.
    Stages:
      1. Enable WSL2 + install Ubuntu   (may require a reboot — re-run after)
      2. Install Miniconda inside WSL
      3. Clone the sam-3d-objects repo
      4. Create conda env + install all pip packages
      5. Download model checkpoints from HuggingFace

.PARAMETER HFToken
    Your HuggingFace read token (hf_...). Required for checkpoint download.
    Get one at: https://huggingface.co/settings/tokens

.EXAMPLE
    # Run without token — skips checkpoint download
    .\setup.ps1

    # Run with token — fully automated
    .\setup.ps1 -HFToken "hf_yourTokenHere"
#>

param(
    [string]$HFToken = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Skip([string]$msg) {
    Write-Host "    [SKIP] $msg (already done)" -ForegroundColor Yellow
}

function Invoke-WSL([string]$cmd) {
    $result = wsl -e bash -ic $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed (exit $LASTEXITCODE): $cmd"
    }
    return $result
}

function Test-WSLCommand([string]$cmd) {
    $out = wsl -e bash -ic "command -v $cmd 2>/dev/null" 2>$null
    return ($LASTEXITCODE -eq 0 -and $out -ne "")
}

function Test-WSLPath([string]$path) {
    wsl -e bash -ic "test -e $path" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ── stage 1: WSL + Ubuntu ──────────────────────────────────────────────────

Write-Step "Stage 1: WSL2 + Ubuntu"

$wslDistros = wsl -l -v 2>$null
$ubuntuInstalled = $wslDistros -match "Ubuntu"

if ($ubuntuInstalled) {
    Write-Skip "Ubuntu already installed in WSL"
} else {
    Write-Host "    Installing WSL2 + Ubuntu..." -ForegroundColor White
    Write-Host "    NOTE: This will require a reboot. Re-run setup.ps1 after reboot." -ForegroundColor Yellow

    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        Write-Host "    ERROR: Please run PowerShell as Administrator to install WSL." -ForegroundColor Red
        exit 1
    }

    wsl --install -d Ubuntu
    Write-Host "`n    WSL + Ubuntu installation started." -ForegroundColor Green
    Write-Host "    After the reboot and Ubuntu first-launch setup (create a username/password)," -ForegroundColor White
    Write-Host "    re-run this script to continue." -ForegroundColor White
    exit 0
}

# ── stage 2: Miniconda ────────────────────────────────────────────────────

Write-Step "Stage 2: Miniconda"

if (Test-WSLPath "~/miniconda3/bin/conda") {
    Write-Skip "Miniconda already installed"
} else {
    Write-Host "    Downloading and installing Miniconda..." -ForegroundColor White
    Invoke-WSL "curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o ~/miniconda.sh && bash ~/miniconda.sh -b -p ~/miniconda3 && rm ~/miniconda.sh" | Out-Null
    Invoke-WSL "~/miniconda3/bin/conda init bash" | Out-Null
    # Accept TOS
    Invoke-WSL "~/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null; ~/miniconda3/bin/conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null; true" | Out-Null
    Write-Ok "Miniconda installed"
}

# ── stage 3: Clone repo ───────────────────────────────────────────────────

Write-Step "Stage 3: Clone sam-3d-objects"

if (Test-WSLPath "~/sam-3d-objects/.git") {
    Write-Skip "Repo already cloned at ~/sam-3d-objects"
} else {
    Write-Host "    Cloning repository..." -ForegroundColor White
    Invoke-WSL "cd ~ && git clone https://github.com/facebookresearch/sam-3d-objects.git" | Out-Null
    Write-Ok "Repo cloned"
}

# ── stage 4a: Conda env ───────────────────────────────────────────────────

Write-Step "Stage 4a: Conda environment (sam3d-objects)"

$condaEnvs = Invoke-WSL "source ~/miniconda3/etc/profile.d/conda.sh && conda env list"
if ($condaEnvs -match "sam3d-objects") {
    Write-Skip "Conda env 'sam3d-objects' already exists"
} else {
    Write-Host "    Creating conda env from environments/default.yml..." -ForegroundColor White
    Write-Host "    (This downloads ~4 GB including CUDA toolkit — may take 10-20 min)" -ForegroundColor Yellow
    Invoke-WSL "source ~/miniconda3/etc/profile.d/conda.sh && cd ~/sam-3d-objects && conda env create -f environments/default.yml" | Out-Null
    Write-Ok "Conda env created"
}

# ── stage 4b: Pip packages ────────────────────────────────────────────────

Write-Step "Stage 4b: Pip packages"

$pipCheck = wsl -e bash -ic "source ~/miniconda3/etc/profile.d/conda.sh && conda activate sam3d-objects && python -c 'import sam3d_objects' 2>/dev/null && echo OK" 2>$null
if ($pipCheck -match "OK") {
    Write-Skip "sam3d_objects package already installed"
} else {
    $pipEnv = "source ~/miniconda3/etc/profile.d/conda.sh && conda activate sam3d-objects && cd ~/sam-3d-objects"
    $extraIdx = "export PIP_EXTRA_INDEX_URL='https://pypi.ngc.nvidia.com https://download.pytorch.org/whl/cu121'"
    $findLinks = "export PIP_FIND_LINKS='https://nvidia-kaolin.s3.us-east-2.amazonaws.com/torch-2.5.1_cu121.html'"

    Write-Host "    pip install .[dev] ..." -ForegroundColor White
    Invoke-WSL "$pipEnv && $extraIdx && pip install -e '.[dev]' -q" | Out-Null
    Write-Ok ".[dev] installed"

    Write-Host "    pip install .[p3d] (builds PyTorch3D + flash-attn, ~10-20 min)..." -ForegroundColor White
    Invoke-WSL "$pipEnv && $extraIdx && pip install -e '.[p3d]' -q" | Out-Null
    Write-Ok ".[p3d] installed"

    Write-Host "    pip install .[inference] ..." -ForegroundColor White
    Invoke-WSL "$pipEnv && $extraIdx && $findLinks && pip install -e '.[inference]' -q" | Out-Null
    Write-Ok ".[inference] installed"

    Write-Host "    Applying hydra patch..." -ForegroundColor White
    Invoke-WSL "$pipEnv && ./patching/hydra" | Out-Null
    Write-Ok "Hydra patch applied"

    Write-Host "    Installing diff-gaussian-rasterization mip-splatting fork (compiling CUDA extension, ~5-10 min)..." -ForegroundColor White
    Invoke-WSL "$pipEnv && pip install 'git+https://github.com/autonomousvision/mip-splatting.git#subdirectory=submodules/diff-gaussian-rasterization' -q" | Out-Null
    Write-Ok "diff-gaussian-rasterization installed"

    Write-Host "    Installing nvdiffrast (required for UV texture baking)..." -ForegroundColor White
    # pip-system-certs interferes with the nvdiffrast build; remove it first, then
    # use --no-build-isolation so the build can find the already-installed PyTorch.
    Invoke-WSL "$pipEnv && pip uninstall pip-system-certs -y 2>/dev/null; pip install --no-build-isolation 'git+https://github.com/NVlabs/nvdiffrast.git' -q" | Out-Null
    Write-Ok "nvdiffrast installed"
}

# ── stage 4c: Copy server.py to WSL ──────────────────────────────────────

Write-Step "Stage 4c: Copy server.py"

$scriptDir = $PSScriptRoot
Invoke-WSL "cp /mnt/$(($scriptDir -replace '\\', '/' -replace ':', '').ToLower())/server.py ~/sam-3d-objects/server.py" | Out-Null
Write-Ok "server.py copied to ~/sam-3d-objects/"

# ── stage 5: Checkpoints ─────────────────────────────────────────────────

Write-Step "Stage 5: Model checkpoints"

if (Test-WSLPath "~/sam-3d-objects/checkpoints/hf/pipeline.yaml") {
    Write-Skip "Checkpoints already downloaded at ~/sam-3d-objects/checkpoints/hf/"
} else {
    if ($HFToken -eq "") {
        Write-Host "    No HuggingFace token provided. Skipping checkpoint download." -ForegroundColor Yellow
        Write-Host "    To download checkpoints, re-run with:" -ForegroundColor White
        Write-Host "        .\setup.ps1 -HFToken 'hf_yourTokenHere'" -ForegroundColor White
        Write-Host "    Get a free read token at: https://huggingface.co/settings/tokens" -ForegroundColor White
    } else {
        Write-Host "    Logging in to HuggingFace..." -ForegroundColor White
        $loginCmd = "source ~/miniconda3/etc/profile.d/conda.sh && conda activate sam3d-objects && hf auth login --token $HFToken"
        Invoke-WSL $loginCmd | Out-Null

        Write-Host "    Downloading checkpoints from facebook/sam-3d-objects (~2 GB)..." -ForegroundColor White
        $dlBase = "source ~/miniconda3/etc/profile.d/conda.sh && conda activate sam3d-objects && cd ~/sam-3d-objects"
        Invoke-WSL "$dlBase && hf download --repo-type model --local-dir checkpoints/hf-download --max-workers 1 facebook/sam-3d-objects" | Out-Null
        Invoke-WSL "cd ~/sam-3d-objects && mv checkpoints/hf-download/checkpoints checkpoints/hf && rm -rf checkpoints/hf-download" | Out-Null
        Write-Ok "Checkpoints downloaded"
    }
}

# ── done ─────────────────────────────────────────────────────────────────

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  SAM3D setup complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Start the server:   .\start_server.bat" -ForegroundColor White
Write-Host "  Server URL:         http://localhost:8000" -ForegroundColor White
Write-Host "  Health check:       http://localhost:8000/health" -ForegroundColor White
Write-Host "  API docs:           http://localhost:8000/docs" -ForegroundColor White
Write-Host "============================================`n" -ForegroundColor Green
