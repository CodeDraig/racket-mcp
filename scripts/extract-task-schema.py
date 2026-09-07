#!/usr/bin/env python3
"""Extract the pinned MCP Tasks result shapes for native runtime validation, offline."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
relative = "schema/2026-07-28/schema.json"
source = root / "vendor/tasks" / relative
lock = json.loads((root / "vendor/LOCK.json").read_text())["tasks"]
if hashlib.sha256(source.read_bytes()).hexdigest() != lock["files"][relative]:
    raise ValueError("Tasks pin mismatch")
schema = json.loads(source.read_text())
selected = {}
pending = ["CreateTaskResult", "GetTaskResult", "UpdateTaskResult", "CancelTaskResult"]

def references(value):
    if isinstance(value, dict):
        if "$ref" in value:
            ref = value["$ref"]
            if not ref.startswith("#/$defs/"):
                raise ValueError("unsupported schema reference: " + ref)
            pending.append(ref.removeprefix("#/$defs/"))
        for child in value.values():
            references(child)
    elif isinstance(value, list):
        for child in value:
            references(child)

while pending:
    name = pending.pop()
    if name not in selected:
        selected[name] = schema["$defs"][name]
        references(selected[name])
result = {"$schema": schema["$schema"], "$defs": selected,
          "$comment": "Extracted from MCP Tasks " + lock["commit"] + "; run scripts/extract-task-schema.py to refresh."}
encoded = (json.dumps(result, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()
target = root / "mcp/private/task-schema.json"
if "--check" in sys.argv:
    if target.read_bytes() != encoded:
        raise ValueError("task schema extraction is stale")
else:
    target.write_bytes(encoded)
print(f"Pinned task schema: {len(selected)} definitions verified")
