"""Filesystem storage for uploaded images, served by FastAPI at /uploads.

Images are saved under uploads/<yyyy>/<mm>/<uuid>.<ext>. The DB stores the
relative path (posix-style, e.g. '2026/05/abc123.jpg'); clients build the URL
as `<baseUrl>/uploads/<relative path>`.
"""
from pathlib import Path
from datetime import datetime
import uuid

UPLOADS_DIR = Path(__file__).resolve().parent / "uploads"
UPLOADS_DIR.mkdir(exist_ok=True)


def save_bytes(data: bytes, ext: str = "jpg") -> str:
    now = datetime.utcnow()
    rel_dir = Path(f"{now:%Y}") / f"{now:%m}"
    abs_dir = UPLOADS_DIR / rel_dir
    abs_dir.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}.{ext}"
    (abs_dir / name).write_bytes(data)
    return (rel_dir / name).as_posix()


def delete_file(rel_path: str) -> bool:
    """Delete a previously saved upload given its DB-relative path
    (e.g. '2026/05/abc.jpg'). Returns True if a file was removed.
    Guards against path traversal — only deletes inside UPLOADS_DIR."""
    if not rel_path:
        return False
    path = (UPLOADS_DIR / rel_path).resolve()
    base = UPLOADS_DIR.resolve()
    if not path.is_relative_to(base):
        return False
    try:
        if path.is_file():
            path.unlink()
            return True
    except OSError:
        return False
    return False
