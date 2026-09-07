#!/usr/bin/env python3
"""Prepare the pinned, locally patched syntax-spec dependency without installation.

The vendor snapshot stays byte-for-byte upstream. No network access is performed.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "vendor" / "syntax-spec-v3"
DESTINATION = ROOT / ".cache" / "patched-dependencies" / "syntax-spec-v3"
COMMIT = "4ae36610804b58e8f023574bfdcba1b5ae4f7bcd"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare():
    lock = json.loads((ROOT / "vendor" / "LOCK.json").read_text())["syntax-spec-v3"]
    if lock["commit"] != COMMIT:
        raise ValueError("syntax-spec patch requires the reviewed upstream commit")
    contents = {}
    for relative, expected in lock["files"].items():
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("invalid source path in syntax-spec lock")
        data = (SOURCE / path).read_bytes()
        if digest(data) != expected:
            raise ValueError(f"syntax-spec source hash mismatch: {relative}")
        contents[relative] = data

    compiler = "private/ee-lib/main.rkt"
    before = contents[compiler]
    old = b"(datum->syntax #f\n                  (if (show-var-numbers)"
    new = (b"(datum->syntax (and (eq? (syntax-local-context) 'module) id)\n"
           b"                  (if (show-var-numbers)")
    if before.count(old) != 1:
        raise ValueError("syntax-spec module temporary patch does not apply uniquely")
    contents[compiler] = before.replace(old, new)
    table = "private/ee-lib/persistent-id-table.rkt"
    table_before = contents[table]
    table_old = b"(make-free-id-table)"
    table_new = (b"(make-free-id-table #:phase "
                 b"(sub1 (variable-reference->module-base-phase (#%variable-reference))))")
    if table_before.count(table_old) != 2:
        raise ValueError("syntax-spec persistent table patch does not apply uniquely")
    contents[table] = table_before.replace(table_old, table_new)
    old_version = b'(define version "0.1")'
    if contents["info.rkt"].count(old_version) != 1:
        raise ValueError("syntax-spec version patch does not apply uniquely")
    contents["info.rkt"] = contents["info.rkt"].replace(
        old_version, b'(define version "0.1.0.1")')

    # Keep generated Racket compilation files when an identical dependency has
    # already been prepared. All inputs are verified before any output changes.
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for relative, data in contents.items():
        target = DESTINATION / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    record = dict(upstream_commit=COMMIT, patch="mcp-phase-bindings-v1",
                  upstream_compiler_sha256=digest(before),
                  patched_compiler_sha256=digest(contents[compiler]),
                  upstream_table_sha256=digest(table_before),
                  patched_table_sha256=digest(contents[table]),
                  version="0.1.0.1")
    (DESTINATION / "MCP-PATCH.json").write_text(json.dumps(record, indent=2) + "\n")
    print(DESTINATION)


if __name__ == "__main__":
    prepare()
