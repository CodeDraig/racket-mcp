#!/usr/bin/env python3
"""Run native Racket release checks with platform-native paths and saved evidence."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-bootstrap", action="store_true")
    parser.add_argument("--package-home", type=Path, default=ROOT / ".cache/ci/package-home")
    args = parser.parse_args()
    logs = ROOT / ".cache/ci/results"
    logs.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / ".cache/ci/tmp"
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, PLTUSERHOME=str(args.package_home.resolve()),
               PLTCOLLECTS=str(ROOT) + os.pathsep, TMPDIR=str(scratch),
               TMP=str(scratch), TEMP=str(scratch))
    installed_env = env.copy()
    installed_env.pop("PLTCOLLECTS", None)
    report = {"platform": platform.platform(), "architecture": platform.machine(),
              "python": platform.python_version(), "steps": [], "success": False}

    def run(name, command, *, installed=False):
        path = logs / (name + ".log")
        print(f"Starting {name}: {json.dumps(command)}", flush=True)
        started = time.monotonic()
        with path.open("wb") as output:
            result = subprocess.run(command, cwd=ROOT, env=installed_env if installed else env,
                                    stdout=output, stderr=subprocess.STDOUT, check=False)
        report["steps"].append({"name": name, "command": command, "exit_code": result.returncode,
                                "seconds": round(time.monotonic() - started, 3), "log": path.name})
        (logs / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Finished {name}: exit {result.returncode}", flush=True)
        if result.returncode:
            print(path.read_text(encoding="utf-8", errors="replace")[-16000:], flush=True)
            raise SystemExit(result.returncode)

    try:
        run("racket-version", ["racket", "--version"])
        run("elicitation-pin", [sys.executable, "scripts/extract-elicitation-schema.py", "--check"])
        run("tasks-pin", [sys.executable, "scripts/extract-task-schema.py", "--check"])
        if not args.skip_bootstrap:
            run("prepare-language", [sys.executable, "scripts/prepare-syntax-spec.py"])
            run("install-language", ["raco", "pkg", "install", "--scope", "user", "--skip-installed",
                "--auto", "--batch", "--no-docs", "--name", "syntax-spec-v3", "--link",
                str(ROOT / ".cache/patched-dependencies/syntax-spec-v3")], installed=True)
        run("distribution", [sys.executable, "scripts/package.py"])
        if not args.skip_bootstrap:
            run("install-sdk", ["raco", "pkg", "install", "--scope", "user", "--skip-installed",
                "--batch", "--no-setup", "--name", "racket-mcp", "--link",
                str(ROOT / ".cache/distribution/racket-mcp")], installed=True)
        sources = [str(path.relative_to(ROOT)) for folder in ("mcp", "examples", "tests", "dev")
                   for path in sorted((ROOT / folder).glob("*.rkt"))]
        run("compile", ["raco", "make", *sources])
        run("native-tests", ["raco", "test", "tests"])
        run("schema-suite", ["racket", "tests/schema-suite.rkt"])
        run("manual", ["raco", "scribble", "+m", "--htmls", "--dest", ".cache/manual", "mcp/scribblings/mcp.scrbl"])
        run("package-dependencies", ["raco", "setup", "--check-pkg-deps", "--pkgs", "racket-mcp"], installed=True)
        report["success"] = True
    finally:
        (logs / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Native verification passed; evidence: " + str(logs), flush=True)


if __name__ == "__main__":
    main()
