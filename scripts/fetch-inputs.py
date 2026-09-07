#!/usr/bin/env python3
"""Explicit, pinned upstream snapshot download. Never runs during expansion."""
import hashlib, io, json, pathlib, tarfile, urllib.request, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = {
    "uri-template-tests": ("uri-templates/uritemplate-test", "4171dac22aa67fc710b3f6df308a50bd08552986", ("LICENSE", "README.md", "extended-tests.json", "negative-tests.json", "spec-examples-by-section.json", "spec-examples.json")),
    "go-sdk": ("modelcontextprotocol/go-sdk", "a5026ea7b727a59b166a06cf7ec4931a50cef427", ("",)),
    "conformance": ("modelcontextprotocol/conformance", "7022d786071e6d868dcd5cf19a8c30db7d811537", ("",)),
    "metaschemas": ("json-schema-org/json-schema-spec", "601a66c8b0f25246bf0e1fb488c5b5f030a79b72", ("schema.json", "meta/", "jsonschema-core", "jsonschema-validation")),
    "protocol": ("modelcontextprotocol/modelcontextprotocol", "e76e9c572c6f2bfcb730357101acc90f2f802e02", ("schema/2026-07-28/", "docs/specification/2026-07-28/")),
    "tasks": ("modelcontextprotocol/ext-tasks", "9263312d11a682ac83f83fe84794d4627efd22f5", ("schema/2026-07-28/", "README.md")),
    "json-schema-tests": ("json-schema-org/JSON-Schema-Test-Suite", "f6fd52a0a95472e079cbfc6ef7f089702b80e045", ("tests/draft2020-12/", "remotes/", "LICENSE")),
}
lock_path = ROOT / "vendor" / "LOCK.json"
lock = json.loads(lock_path.read_text()) if lock_path.exists() else {}
for name, (repo, commit, prefixes) in SOURCES.items():
    if len(sys.argv) > 1 and name not in sys.argv[1:]:
        continue
    url = f"https://codeload.github.com/{repo}/tar.gz/{commit}"
    data = urllib.request.urlopen(url, timeout=60).read()
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive.getmembers():
            relative = member.name.partition("/")[2]
            path = pathlib.PurePosixPath(relative)
            if not member.isfile() or ".." in path.parts or path.is_absolute():
                continue
            if not any(relative.startswith(p) for p in prefixes) and relative not in ("LICENSE", "LICENSE.md"):
                continue
            content = archive.extractfile(member).read()
            dest = ROOT / "vendor" / name / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(content)
            files[relative] = hashlib.sha256(content).hexdigest()
    lock[name] = dict(repository=repo, commit=commit, files=files)
    print(name, len(files), "files")
(ROOT / "vendor").mkdir(exist_ok=True)
(ROOT / "vendor" / "LOCK.json").write_text(json.dumps(lock, indent=2) + "\n")
