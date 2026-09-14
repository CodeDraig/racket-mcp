#!/usr/bin/env python3
"""Prepare the pinned conformance harness with its registration fixture repaired.

No downloads, installations, SDK modifications, or upstream source changes.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMIT = "7022d786071e6d868dcd5cf19a8c30db7d811537"
FIXTURE = "src/scenarios/client/auth/helpers/createAuthServer.ts"
OLD = b'''      ...(clientSecret && { client_secret: clientSecret }),
      client_name: req.body.client_name || 'test-client',
      redirect_uris: req.body.redirect_uris || [],
      ...(tokenEndpointAuthMethod && {
        token_endpoint_auth_method: tokenEndpointAuthMethod
      })'''
NEW = b'''      ...(clientSecret && { client_secret: clientSecret, client_secret_expires_at: 0 }),
      client_name: req.body.client_name || 'test-client',
      redirect_uris: req.body.redirect_uris || [],
      grant_types: req.body.grant_types || ['authorization_code'],
      response_types: req.body.response_types || ['code'],
      token_endpoint_auth_method: tokenEndpointAuthMethod ??
        (tokenEndpointAuthMethodsSupported.includes(req.body.token_endpoint_auth_method)
          ? req.body.token_endpoint_auth_method : tokenEndpointAuthMethodsSupported[0])'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def repair(data):
    if data.count(OLD) != 1:
        raise ValueError("registration fixture correction does not apply uniquely")
    return data.replace(OLD, NEW)


def prepare(destination, node_modules=None, root=ROOT):
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError("destination already exists; select a fresh preparation directory")
    source = root / "vendor/conformance"
    lock = json.loads((root / "vendor/LOCK.json").read_text())["conformance"]
    if lock["commit"] != COMMIT:
        raise ValueError("conformance correction requires the reviewed upstream commit")
    contents = {}
    for relative, expected in lock["files"].items():
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("invalid conformance lock path")
        data = (source / path).read_bytes()
        if digest(data) != expected:
            raise ValueError(f"conformance source hash mismatch: {relative}")
        contents[relative] = data
    before = contents[FIXTURE]
    contents[FIXTURE] = repair(before)
    modules = None
    if node_modules is not None:
        modules = Path(node_modules).resolve(strict=True)
        if not modules.is_dir() or not (modules / ".bin/tsx").exists():
            raise ValueError("node_modules must contain an existing tsx executable")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".conformance-", dir=destination.parent))
    try:
        for relative, data in contents.items():
            target = temporary / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        manifest = {
            "upstream_commit": COMMIT,
            "classification": "locally corrected fixture; not unmodified conformance",
            "changed_files": {FIXTURE: {"before": digest(before), "after": digest(contents[FIXTURE])}},
            "source_files_verified": len(contents),
            "node_modules": str(modules) if modules else None,
        }
        (temporary / "racket-mcp-fixture-correction.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (temporary / "racket-mcp-fixture-correction.patch").write_text("".join(difflib.unified_diff(
            before.decode().splitlines(True), contents[FIXTURE].decode().splitlines(True),
            fromfile="a/" + FIXTURE, tofile="b/" + FIXTURE)))
        if modules:
            (temporary / "node_modules").symlink_to(modules, target_is_directory=True)
        # Publish only a complete preparation. Never remove a previous output.
        os.rename(temporary, destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".cache/patched-dependencies/conformance")
    parser.add_argument("--node-modules", type=Path, help="optional existing development dependencies; never installed")
    args = parser.parse_args()
    print(json.dumps(prepare(args.output, args.node_modules), indent=2))
