#!/usr/bin/env python3
"""Validate a fresh copy without replacing existing checkout caches or evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--racket-bin", type=Path, required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--work", type=Path, required=True)
parser.add_argument("--results", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work.resolve()
results = args.results.resolve()
work.mkdir(parents=True, exist_ok=False)
results.mkdir(parents=True, exist_ok=False)
paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")[:-1]
manifest = {}
for name in paths:
    if name.startswith("test-artifacts/public-readiness-20261025/"):
        continue
    source = root / name
    target = work / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    manifest[name] = hashlib.sha256(source.read_bytes()).hexdigest()
(results / "source-sha256.json").write_text(json.dumps(manifest, indent=2) + "\n")
env = os.environ.copy()
env.update(PATH=str(args.racket_bin.resolve()) + os.pathsep + env["PATH"],
           PLTUSERHOME=str(work / ".racket"), PLTCOLLECTS=str(work) + os.pathsep,
           TMPDIR=str(work / ".cache/tmp"), MCP_RACKET_USER_HOME=str(work / ".racket"),
           GOFLAGS="-buildvcs=false")
Path(env["TMPDIR"]).mkdir(parents=True)
installed = env.copy()
installed.pop("PLTCOLLECTS", None)
report = {"base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root).decode().strip(),
          "requested_racket": args.version, "work": str(work), "steps": [], "success": False}

def save():
    (results / "report.json").write_text(json.dumps(report, indent=2) + "\n")

def run(name, command, environment=env):
    print("Starting " + args.version + " " + name, flush=True)
    start = time.monotonic()
    with (results / (name + ".log")).open("wb") as output:
        result = subprocess.run(command, cwd=work, env=environment, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT)
    report["steps"].append({"name": name, "command": command, "exit_code": result.returncode,
                            "seconds": round(time.monotonic() - start, 3)})
    save()
    print("Finished " + args.version + " " + name + ": " + str(result.returncode), flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)

try:
    run("racket-version", ["racket", "--version"])
    # README bootstrap, in its documented order, into an empty package home.
    run("prepare-language", ["python3", "scripts/prepare-syntax-spec.py"])
    run("install-language", ["raco", "pkg", "install", "--name", "syntax-spec-v3", "--auto",
        "--batch", "--no-docs", "--link", str(work / ".cache/patched-dependencies/syntax-spec-v3")], installed)
    run("package", ["python3", "scripts/package.py"])
    run("install-sdk", ["raco", "pkg", "install", "--name", "racket-mcp", "--no-setup",
        "--link", str(work / ".cache/distribution/racket-mcp")], installed)
    run("register-sdk", ["raco", "setup", "--no-zo", "--no-docs", "--pkgs", "racket-mcp"], installed)
    run("readme-compile", ["raco", "make", "examples/greeter.rkt"])
    run("readme-greeter-eof", ["racket", "examples/greeter.rkt"])
    # Exercise CI's own bootstrap in a second empty package home as well.
    run("native-ci", ["python3", "scripts/ci.py", "--package-home", str(work / ".cache/ci-package-home")])
    run("go-interop", ["sh", "scripts/check-interop.sh"])
    run("installed-tests", ["raco", "test", "tests/declared-build.rkt", "tests/declared-build-cli.rkt",
                            "tests/cli-artifacts.rkt", "tests/view-adapters.rkt"], installed)
    archive = work / ".cache/distribution/racket-mcp-0.1.zip"
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        report["archive"] = {"sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                             "bytes": archive.stat().st_size, "files": len(package.namelist()),
                             "integrity": "passed"}
    report["success"] = True
finally:
    ci = work / ".cache/ci/results"
    if ci.exists():
        shutil.copytree(ci, results / "native-ci")
    save()
