"""
SAM3D TouchDesigner Client — paste into a Text DAT named "sam3d_client"

Usage:
    mod('./project1/sam3d_client').check_server()
    mod('./project1/sam3d_client').generate('C:/img.png', 'C:/mask.png', format='glb')
    mod('./project1/sam3d_client').generate('C:/img.png', 'C:/mask.png', format='obj', output_path='C:/out/mesh.obj')
"""

import json
import os
import threading
import urllib.error
import urllib.request

# ── config ────────────────────────────────────────────────────────────────

SERVER_URL  = "http://127.0.0.1:8766"
WORK_DIR    = "C:/Users/Zach/Desktop/Meta_AI/SAM3D/td/work"
OUTPUT_SOP  = "geo1"          # File In SOP to update with the result (set "" to skip)

# ─────────────────────────────────────────────────────────────────────────

_results = {}
_counter = 0
_counter_lock = threading.Lock()


def _next_job_id():
    global _counter
    with _counter_lock:
        _counter += 1
        return _counter


def check_server():
    """Check server health and print status to Textport."""
    try:
        req = urllib.request.Request(f"{SERVER_URL}/health")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        status = data.get("status", "unknown")
        busy   = data.get("busy", False)
        print(f"[SAM3D] Server {status} | busy={busy}")
        return status == "ok"
    except urllib.error.URLError as e:
        print(f"[SAM3D] Server unreachable: {e.reason}")
        return False


def generate(
    image_path,
    mask_path=None,
    format="glb",
    output_path=None,
    seed=42,
    texture_baking=True,
    texture_size=1024,
):
    """
    Non-blocking — runs inference in a background thread.

    Args:
        image_path:     Windows path to the input RGB image.
        mask_path:      Windows path to the binary mask (grayscale). Optional —
                        if omitted, the full image is reconstructed.
        format:         "glb" (default) or "obj".
        output_path:    Where to save the result. Defaults to WORK_DIR/output.<ext>.
        seed:           Random seed.
        texture_baking: True (default) = UV texture maps. False = vertex colors.
        texture_size:   Texture resolution: 1024 (default), 2048, or 4096.
    """
    if output_path is None:
        ext = "glb" if format == "glb" else "obj"
        output_path = os.path.join(WORK_DIR, f"output.{ext}").replace("\\", "/")

    job_id = _next_job_id()
    print(f"[SAM3D] Job {job_id} started (format={format}, seed={seed}, texture_baking={texture_baking}, texture_size={texture_size})")

    thread = threading.Thread(
        target=_worker,
        args=(job_id, image_path, mask_path, format, output_path, seed, texture_baking, texture_size),
        daemon=True,
    )
    thread.start()
    return job_id


def _worker(job_id, image_path, mask_path, format, output_path, seed, texture_baking, texture_size):
    payload = {
        "image_path":     image_path.replace("\\", "/"),
        "output_path":    output_path.replace("\\", "/"),
        "format":         format,
        "seed":           seed,
        "texture_baking": texture_baking,
        "texture_size":   texture_size,
    }
    if mask_path:
        payload["mask_path"] = mask_path.replace("\\", "/")

    body = json.dumps(payload).encode("utf-8")

    req = urllib.request.Request(
        f"{SERVER_URL}/generate",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            result = json.loads(resp.read())
        _results[job_id] = result
        run("args[0](args[1], args[2])", [_finish, job_id, result], delayFrames=1)

    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="replace")
        print(f"[SAM3D] Job {job_id} failed ({e.code}): {msg}")
    except urllib.error.URLError as e:
        print(f"[SAM3D] Job {job_id} connection error: {e.reason}")
    except Exception as e:
        print(f"[SAM3D] Job {job_id} error: {e}")


def _finish(job_id, result):
    """Called on the TD main thread after inference completes."""
    out = result.get("output_path", "")
    fmt = result.get("format", "")
    print(f"[SAM3D] Job {job_id} done → {out}")

    if OUTPUT_SOP and out:
        try:
            op(OUTPUT_SOP).par.file = out
            op(OUTPUT_SOP).par.reloadpulse.pulse()
            print(f"[SAM3D] Loaded into {OUTPUT_SOP}")
        except Exception as e:
            print(f"[SAM3D] Could not update {OUTPUT_SOP}: {e}")
