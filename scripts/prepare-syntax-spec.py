#!/usr/bin/env python3
"""Reproduce the installable, namespaced syntax-spec dependency without installation.

The vendor snapshot stays byte-for-byte upstream. No network access is performed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "vendor" / "syntax-spec-v3"
PACKAGE = "mcp-syntax-spec-v3"
DESTINATION = ROOT / "packages" / PACKAGE
COMMIT = "4ae36610804b58e8f023574bfdcba1b5ae4f7bcd"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(destination=DESTINATION, *, check=False, archive=None):
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
    references = "private/runtime/compile.rkt"
    references_before = contents[references]
    replacements = (
        (b"  (define (binding-as-rkt bclass-id description)",
         b"  (define (binding-as-rkt bclass-id description [default-compiler #f])"),
        (b"                              error-as-rkt)))",
         b"                              (lambda () (or default-compiler (error-as-rkt))))))"),
    )
    for old, new in replacements:
        if contents[references].count(old) != 1:
            raise ValueError("syntax-spec reference default patch does not apply uniquely")
        contents[references] = contents[references].replace(old, new)
    interface = "private/syntax/interface.rkt"
    interface_before = contents[interface]
    replacements = (
        (b"(binding-as-rkt (quote-syntax name) (#%datum . descr.str))",
         b"(binding-as-rkt (quote-syntax name) (#%datum . descr.str)\n"
         b"                                (~? (delay reference-compiler.compiler) #f))"),
        (b"                 (quote space.stx)))\n"
         b"              (~? (add-global-reference-compiler! #'name (delay reference-compiler.compiler))))",
         b"                 (quote space.stx))))"),
    )
    for old, new in replacements:
        if contents[interface].count(old) != 1:
            raise ValueError("syntax-spec binding default patch does not apply uniquely")
        contents[interface] = contents[interface].replace(old, new)
    old_version = b'(define version "0.1")'
    if contents["info.rkt"].count(old_version) != 1:
        raise ValueError("syntax-spec version patch does not apply uniquely")
    contents["info.rkt"] = contents["info.rkt"].replace(
        old_version, b'(define version "0.1.0.2")')

    record = dict(upstream_commit=COMMIT, patch="mcp-phase-and-reference-bindings-v2",
                  upstream_compiler_sha256=digest(before),
                  patched_compiler_sha256=digest(contents[compiler]),
                  upstream_table_sha256=digest(table_before),
                  patched_table_sha256=digest(contents[table]),
                  upstream_reference_sha256=digest(references_before),
                  patched_reference_sha256=digest(contents[references]),
                  upstream_interface_sha256=digest(interface_before),
                  patched_interface_sha256=digest(contents[interface]),
                  version="0.1.0.2", package=PACKAGE, collection=PACKAGE)
    # Rename collection references in code and manuals, including upstream test
    # languages. Keep the compiler patches above unchanged and the vendor intact.
    for relative, data in contents.items():
        if Path(relative).suffix in (".rkt", ".scrbl"):
            contents[relative] = data.replace(b"syntax-spec-v3", PACKAGE.encode())
    contents["info.rkt"] += (
        b'\n(define pkg-desc "MCP-specific syntax-spec v3 with phase and reference-binding fixes")\n')
    contents["Racket-MIT.txt"] = (ROOT / "LICENSES" / "Racket-MIT.txt").read_bytes()
    contents["MCP-PACKAGE.md"] = f"""# {PACKAGE}

An MCP-specific patched copy of syntax-spec v3, version 0.1.0.2.
Upstream: https://github.com/michaelballantyne/syntax-spec/tree/{COMMIT}

Package and collection name: `{PACKAGE}`. Use `(require {PACKAGE})`.
The distinct collection can coexist with upstream `syntax-spec-v3`; this is
not an upstream release or a replacement for that package.

Changes preserve module-level declaration scopes, compare persistent bindings
at their compiler phase, and attach delayed reference defaults to binding-class
transformers. Collection references in source, tests, and manuals are renamed.
The compiler behavior patches are the same as the SDK's previously tested
local version 0.1.0.2. MCP-PATCH.json records provenance and generated file hashes.

This directory is an installable single-collection Racket package. From its
parent directory: `raco pkg install --auto ./mcp-syntax-spec-v3`.
No Python preparation step is needed by package consumers.

Maintainers reproduce it from the racket-mcp repository root with
`python3 scripts/prepare-syntax-spec.py`, verify it with `--check`, and optionally
write a reproducible source ZIP with `--archive PATH`.
The original snapshot under vendor/syntax-spec-v3 is never changed.

Original upstream copyright and license notices are retained. This distribution
uses the MIT option for the upstream Apache-2.0-or-MIT material; Racket-MIT.txt
contains that license text. The upstream tests/dsls/tiny-hdl sources retain their
MPL-2.0 license and its included LICENSE file. See LICENSE and those source files.
The upstream README.md is retained as upstream documentation.
""".encode()
    contents["README.md"] = (
        f"# {PACKAGE}\n\n"
        "This directory contains the MCP-specific patched package, version 0.1.0.2.\n"
        f"Install it with `raco pkg install --auto ./{PACKAGE}` from its parent\n"
        f"directory and import it with `(require {PACKAGE})`. It can coexist\n"
        "with upstream syntax-spec-v3. See [package details](MCP-PACKAGE.md)\n"
        "for the patches, reproduction commands, and licenses.\n\n"
        "## Original upstream README\n\n"
        "The installation commands below describe the upstream package, not this\n"
        "patched copy. Use the installation and import commands above for MCP.\n\n"
    ).encode() + contents["README.md"]
    record["files"] = {name: digest(data) for name, data in sorted(contents.items())}
    contents["MCP-PATCH.json"] = (json.dumps(record, indent=2) + "\n").encode()
    # Refuse to discard unexpected source files. Compilation caches are not
    # package inputs and are neither touched nor included in the archive.
    if destination.exists():
        extras = [p.relative_to(destination).as_posix() for p in destination.rglob("*")
                  if p.is_file() and not any(part in ("compiled", "doc")
                                            for part in p.relative_to(destination).parts)
                  and p.relative_to(destination).as_posix() not in contents]
        if extras:
            raise ValueError(f"unexpected package files (preserved): {extras}")
    if check:
        mismatches = [name for name, data in contents.items()
                      if not (destination / name).is_file()
                      or (destination / name).read_bytes() != data]
        if mismatches:
            raise ValueError(f"generated package differs: {mismatches}")
    else:
        for relative, data in contents.items():
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_bytes() != data:
                target.write_bytes(data)
    if archive:
        archive.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
            for relative, data in sorted(contents.items()):
                entry = zipfile.ZipInfo(PACKAGE + "/" + relative, (2026, 9, 7, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(entry, data)
        print(f"{digest(archive.read_bytes())}  {archive}")
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DESTINATION)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    prepare(args.output, check=args.check, archive=args.archive)
