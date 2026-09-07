#!/usr/bin/env python3
"""Build an isolated source distribution without caches or compiled artifacts."""
from pathlib import Path
import shutil, hashlib, zipfile
root = Path(__file__).resolve().parents[1]
destination = root / ".cache" / "distribution" / "racket-mcp"
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
for name in ("mcp", "examples", "tests", "scripts", "vendor", "dev"):
    shutil.copytree(root / name, destination / name,
                    ignore=shutil.ignore_patterns("compiled", "node_modules", ".git", "results", "__pycache__", "*.pyc"))
for name in ("info.rkt", "README.md", "IMPLEMENTATION.md"):
    shutil.copy2(root / name, destination / name)
print(destination)
archive = destination.parent / "racket-mcp-0.1.zip"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
    for path in sorted(destination.rglob("*")):
        if not path.is_file():
            continue
        entry = zipfile.ZipInfo("racket-mcp/" + path.relative_to(destination).as_posix(), (2026, 9, 7, 0, 0, 0))
        entry.create_system = 3
        entry.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
        entry.compress_type = zipfile.ZIP_DEFLATED
        output.writestr(entry, path.read_bytes())
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(destination.parent / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
print(archive)
