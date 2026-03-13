"""
SAM3D Server

Endpoints:
  GET  /health    — model status, device, busy flag
  POST /generate  — generate 3D mesh from image + mask paths

Request body (JSON):
  {
    "image_path":  "C:/path/to/image.png",
    "mask_path":   "C:/path/to/mask.png",
    "output_path": "C:/path/to/output.glb",
    "format":      "glb",   // "glb" (default) or "obj"
    "seed":        42
  }

Response:
  { "output_path": "C:/path/to/output.glb", "format": "glb" }
  { "output_path": "C:/path/to/output.obj", "format": "obj", "files": [...] }
"""

import sys
import logging
import threading
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).parent / "notebook"))
from inference import Inference  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

PORT = 8766
CONFIG_PATH = str(Path(__file__).parent / "checkpoints/hf/pipeline.yaml")

_inference: Inference | None = None
_lock = threading.Lock()


# ── path helpers ──────────────────────────────────────────────────────────

def win_to_wsl(path: str) -> str:
    """C:\\Users\\foo\\bar.png  →  /mnt/c/Users/foo/bar.png"""
    path = path.replace("\\", "/")
    if len(path) >= 2 and path[1] == ":":
        drive = path[0].lower()
        path = f"/mnt/{drive}{path[2:]}"
    return path


# ── lifespan ──────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _inference
    log.info("Loading SAM3D model...")
    _inference = Inference(CONFIG_PATH, compile=False)
    log.info("Model ready.")
    yield
    _inference = None


app = FastAPI(title="SAM3D Server", version="1.0.0", lifespan=lifespan)


# ── request / response models ────────────────────────────────────────────

class GenerateRequest(BaseModel):
    image_path: str
    mask_path: Optional[str] = None   # omit to reconstruct the full image
    output_path: str
    format: str = "glb"
    seed: int = 42
    texture_baking: bool = True       # True = UV textures, False = vertex colors


# ── endpoints ────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "ok" if _inference is not None else "loading",
        "busy": _lock.locked(),
    }


@app.post("/generate")
def generate(req: GenerateRequest):
    if _inference is None:
        raise HTTPException(503, detail="Model is still loading, try again shortly.")

    fmt = req.format.lower()
    if fmt not in ("glb", "obj"):
        raise HTTPException(400, detail=f"Unsupported format '{req.format}'. Use 'glb' or 'obj'.")

    if not _lock.acquire(blocking=False):
        raise HTTPException(503, detail="Server is busy with another request.")

    try:
        img_wsl = win_to_wsl(req.image_path)
        out_wsl = win_to_wsl(req.output_path)

        img = np.array(Image.open(img_wsl).convert("RGB"))

        if req.mask_path:
            mask = np.array(Image.open(win_to_wsl(req.mask_path)).convert("L")) > 0
        else:
            # No mask provided — reconstruct the full image
            mask = np.ones(img.shape[:2], dtype=bool)
            log.info("No mask provided, using full-image mask.")

        log.info("Running inference (format=%s, seed=%d, texture_baking=%s)...", fmt, req.seed, req.texture_baking)
        rgba = _inference.merge_mask_to_rgba(img, mask)
        output = _inference._pipeline.run(
            rgba,
            None,
            req.seed,
            stage1_only=False,
            with_mesh_postprocess=False,
            with_texture_baking=req.texture_baking,
            with_layout_postprocess=False,
            use_vertex_color=not req.texture_baking,
            stage1_inference_steps=None,
        )
        log.info("Inference complete.")

        out_path = Path(out_wsl)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        if fmt == "glb":
            out_path.write_bytes(output["glb"].export(file_type="glb"))
            return {"output_path": req.output_path, "format": "glb"}

        # obj — trimesh writes .obj + .mtl + textures into the same directory
        output["glb"].export(str(out_path))
        files_win = [
            req.output_path.replace(out_path.name, f.name)
            for f in out_path.parent.iterdir()
            if f.suffix in (".obj", ".mtl", ".png", ".jpg")
        ]
        return {"output_path": req.output_path, "format": "obj", "files": files_win}

    except HTTPException:
        raise
    except Exception as exc:
        log.exception("Inference failed")
        raise HTTPException(500, detail=str(exc)) from exc
    finally:
        _lock.release()


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
