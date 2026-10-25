#!/usr/bin/env python3
"""Repeat the recorded conformance legs, preserving their original qualifications.

Uses the existing development harness dependencies; no npm installation or changes.
Raw results stay in the supplied fresh cache directory. Commands, logs, hashes,
status counts and every failed/warned/skipped check are copied into this record.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--work", type=Path, required=True)
parser.add_argument("--raw", type=Path, required=True)
parser.add_argument("--results", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
work, raw, results = args.work.resolve(), args.raw.resolve(), args.results.resolve()
raw.mkdir(parents=True, exist_ok=False)
results.mkdir(parents=True, exist_ok=False)
harness = repo / ".cache/conformance-pinned"
corrected = repo / ".cache/public-readiness-20261025/conformance-corrected-harness"
racket_bin = repo / ".cache/racket-9.3/bin"
# tsx uses a Unix-domain IPC socket: keep its pathname below the OS limit.
scratch = repo / ".cache/cf-public-20261025"
scratch.mkdir(exist_ok=True)
env = dict(os.environ, PATH=str(racket_bin) + os.pathsep + os.environ["PATH"],
           PLTCOLLECTS=str(work) + os.pathsep, PLTUSERHOME=str(work / ".racket"),
           TMPDIR=str(scratch))
lock = json.loads((repo / "vendor/LOCK.json").read_text())["conformance"]["files"]
for name, expected in lock.items():
    assert hashlib.sha256((harness / name).read_bytes()).hexdigest() == expected, name
    if name != "src/scenarios/client/auth/helpers/createAuthServer.ts":
        assert hashlib.sha256((corrected / name).read_bytes()).hexdigest() == expected, name
fixture_manifest = json.loads((corrected / "racket-mcp-fixture-correction.json").read_text())
for name, hashes in fixture_manifest["changed_files"].items():
    assert hashlib.sha256((corrected / name).read_bytes()).hexdigest() == hashes["after"], name
shutil.copy2(corrected / "racket-mcp-fixture-correction.json", results / "fixture-correction.json")
shutil.copy2(corrected / "racket-mcp-fixture-correction.patch", results / "fixture-correction.patch")
legs = [
    ("core", "declared-core-20260908/run.py", harness),
    ("tasks", "declared-tasks-corrected-20260908/run.py", harness),
    ("clients", "final-clients-20260908/run.py", harness),
    ("oauth", "oauth-all-scenarios-20260908/corrected-fixture/run.py", corrected),
    ("offline-access", "oauth-offline-access-20260908/run.py", harness),
]
summary = {"racket": "9.3", "source_manifest": "../" + work.name + "/source-sha256.json",
           "harness_commit": "7022d786071e6d868dcd5cf19a8c30db7d811537", "legs": {}}
for name, historical, selected in legs:
    out = raw / name
    out.mkdir()
    script = (repo / "test-artifacts" / historical).read_text()
    script = script.replace("root=pathlib.Path.cwd()", "root=pathlib.Path(" + repr(str(work)) + ")")
    lines = script.splitlines()
    lines = [("out=pathlib.Path(" + repr(str(out)) + ")") if line.startswith("out=") else
             ("harness=pathlib.Path(" + repr(str(selected)) + ")") if line.startswith("harness=") else line
             for line in lines]
    script = "\n".join(lines) + "\n"
    script = script.replace("str(root/'.cache/racket-9.3/bin/racket')", repr(str(racket_bin / "racket")))
    script = script.replace("'/usr/bin/racket '", repr(str(racket_bin / "racket") + " "))
    script = script.replace("TMPDIR=str(root/'.cache/tmp')", "TMPDIR=" + repr(str(scratch)))
    if name == "oauth":
        shutil.copy2(repo / "test-artifacts/oauth-all-scenarios-20260908/corrected-fixture/scenarios.json",
                     out / "scenarios.json")
    driver = out / "run.py"
    driver.write_text(script)
    print("Starting conformance " + name, flush=True)
    with (out / "driver.log").open("w") as log:
        status = subprocess.run(["python3", str(driver)], cwd=work, env=env,
                                stdout=log, stderr=subprocess.STDOUT).returncode
    counts = Counter()
    exceptions = []
    checksums = {}
    for path in sorted((out / "results").rglob("checks.json")):
        checksums[str(path.relative_to(out))] = hashlib.sha256(path.read_bytes()).hexdigest()
        for check in json.loads(path.read_text()):
            counts[check["status"]] += 1
            if check["status"] in ("FAILURE", "WARNING", "SKIPPED"):
                exceptions.append({"artifact": str(path.relative_to(out)), "check": check})
    record = results / name
    record.mkdir()
    for path in out.iterdir():
        if path.is_file():
            shutil.copy2(path, record / path.name)
    (record / "checks-sha256.json").write_text(json.dumps(checksums, indent=2) + "\n")
    summary["legs"][name] = {"driver_exit": status, "counts": dict(counts), "exceptions": exceptions}
    (results / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print("Finished conformance " + name + ": driver=" + str(status) + " " + str(dict(counts)), flush=True)
    if status:
        raise SystemExit(status)
    if not checksums:
        raise SystemExit("No checks.json files produced by " + name + "; inspect harness logs")
