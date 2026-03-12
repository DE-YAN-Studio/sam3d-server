# SAM3D Server

A FastAPI server that wraps [Meta's SAM 3D Objects](https://github.com/facebookresearch/sam-3d-objects) model, exposing a simple HTTP API for generating 3D meshes from images. Designed for integration with [TouchDesigner](https://derivative.ca/).

## Requirements

- Windows 10/11
- WSL2 with Ubuntu
- NVIDIA GPU with 32 GB VRAM
- [HuggingFace account](https://huggingface.co) (free) for downloading model weights

## Setup

Run once from PowerShell (no admin required if WSL is already installed):

```powershell
.\setup.ps1 -HFToken "hf_yourTokenHere"
```

This will:
1. Install Miniconda inside WSL
2. Clone the `sam-3d-objects` repo
3. Create the `sam3d-objects` conda environment
4. Install all dependencies (PyTorch, PyTorch3D, Kaolin, etc.)
5. Download model checkpoints from HuggingFace

> If WSL or Ubuntu are not yet installed, the script will install them and prompt you to reboot, then re-run.

Get a free HuggingFace read token at: https://huggingface.co/settings/tokens

## Starting the Server

Double-click `start_server.bat` and wait for:

```
[INFO] Model ready.
[INFO] Uvicorn running on http://0.0.0.0:8766
```

Model loading takes ~60 seconds. The server runs on **port 8766**.

## API

### `GET /health`
Returns server status and whether it's currently processing a request.

```json
{ "status": "ok", "busy": false }
```

### `POST /generate`
Generate a 3D mesh from an image and optional segmentation mask.

**Request body (JSON):**
```json
{
  "image_path":  "C:/path/to/image.png",
  "mask_path":   "C:/path/to/mask.png",
  "output_path": "C:/path/to/output.glb",
  "format":      "glb",
  "seed":        42
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `image_path` | string | required | Windows path to input RGB image (PNG/JPG) |
| `mask_path` | string | `null` | Windows path to grayscale segmentation mask. If omitted, the full image is reconstructed. |
| `output_path` | string | required | Windows path where the output file will be saved |
| `format` | string | `"glb"` | `"glb"` — single binary file with textures; `"obj"` — OBJ + MTL + textures |
| `seed` | int | `42` | Random seed for reproducibility |

**Response:**
```json
{ "output_path": "C:/path/to/output.glb", "format": "glb" }
```

For `obj`, also includes `"files"` — list of all extracted file paths (`.obj`, `.mtl`, textures).

> The server serializes requests — concurrent calls return `503 busy` while inference is running.

## TouchDesigner Integration

1. Create a **Text DAT** in your network, name it `sam3d_client`
2. Paste the contents of `td/sam3d_client.py` into it
3. Set `OUTPUT_SOP` at the top of the script to the name of your File In SOP
4. Call from any DAT or Textport:

```python
# Check server is ready
mod('./project1/sam3d_client').check_server()

# Generate GLB (non-blocking — result loads into OUTPUT_SOP automatically)
mod('./project1/sam3d_client').generate(r"C:\path\to\image.jpg")

# With segmentation mask
mod('./project1/sam3d_client').generate(
    r"C:\path\to\image.jpg",
    r"C:\path\to\mask.png",
    format="glb",
)

# OBJ format
mod('./project1/sam3d_client').generate(r"C:\path\to\image.jpg", format="obj")
```

The client runs inference in a background thread so TouchDesigner stays responsive. When complete, the result is automatically loaded into the configured SOP.

Output files are saved to `td/work/` by default (configurable via `WORK_DIR` in the script).

## Project Structure

```
SAM3D/
├── server.py           # FastAPI server (runs inside WSL)
├── setup.ps1           # One-shot environment setup script
├── start_server.bat    # Server launcher
├── td/
│   ├── sam3d_client.py # TouchDesigner Script DAT client
│   ├── work/           # Default output directory
│   └── SAM3D-TD.toe    # TouchDesigner project file
└── README.md
```

## Notes

- File paths are automatically translated between Windows (`C:\...`) and WSL (`/mnt/c/...`) by the server
- The `td/sam3d_client.py` uses only Python stdlib (`urllib`, `threading`, `json`) — no external dependencies required inside TouchDesigner
- Interactive API docs available at `http://localhost:8766/docs` while the server is running
