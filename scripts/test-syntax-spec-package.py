#!/usr/bin/env python3
"""Check package reproduction, archive integrity, and refusal of altered inputs."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "prepare_syntax_spec", Path(__file__).with_name("prepare-syntax-spec.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mcp-syntax-package-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / prepare.PACKAGE

    def generate(self, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            prepare.prepare(self.package, **kwargs)

    def test_reproduction_and_archive(self):
        first, second = self.root / "first.zip", self.root / "second.zip"
        self.generate(archive=first)
        self.generate(check=True, archive=second)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        manifest = json.loads((self.package / "MCP-PATCH.json").read_text())
        for name, sha in manifest["files"].items():
            self.assertEqual(prepare.digest((self.package / name).read_bytes()), sha)
        with zipfile.ZipFile(first) as archive:
            names = set(archive.namelist())
            for name in ("info.rkt", "Racket-MIT.txt", "LICENSE",
                         "tests/dsls/tiny-hdl/LICENSE", "MCP-PATCH.json"):
                self.assertIn(prepare.PACKAGE + "/" + name, names)
            self.assertFalse(any("/compiled/" in name for name in names))
        for path in self.package.rglob("*"):
            if path.suffix in (".rkt", ".scrbl"):
                self.assertNotIn(b"syntax-spec-v3", path.read_bytes().replace(
                    b"mcp-syntax-spec-v3", b""))

    def test_check_preserves_changed_file(self):
        self.generate()
        target = self.package / "main.rkt"
        target.write_bytes(b"changed source")
        with self.assertRaisesRegex(ValueError, "generated package differs"):
            self.generate(check=True)
        self.assertEqual(target.read_bytes(), b"changed source")

    def test_unexpected_source_is_preserved(self):
        self.generate()
        extra = self.package / "local-work.rkt"
        extra.write_bytes(b"local work")
        with self.assertRaisesRegex(ValueError, "unexpected package files"):
            self.generate()
        self.assertEqual(extra.read_bytes(), b"local work")

    def test_bad_upstream_fails_before_writing(self):
        source = self.root / "bad-upstream"
        source.mkdir()
        lock = json.loads((prepare.ROOT / "vendor/LOCK.json").read_text())
        for name in lock["syntax-spec-v3"]["files"]:
            target = source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((prepare.SOURCE / name).read_bytes())
        (source / "main.rkt").write_bytes(b"changed upstream")
        original = prepare.SOURCE
        try:
            prepare.SOURCE = source
            with self.assertRaisesRegex(ValueError, "source hash mismatch"):
                self.generate()
        finally:
            prepare.SOURCE = original
        self.assertFalse(self.package.exists())


if __name__ == "__main__":
    unittest.main()
