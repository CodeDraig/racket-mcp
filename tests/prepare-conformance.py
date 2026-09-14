import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_conformance", ROOT / "scripts/prepare-conformance.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / "vendor/conformance"
        fixture = source / module.FIXTURE
        fixture.parent.mkdir(parents=True)
        fixture.write_bytes(b"before\n" + module.OLD + b"\nafter\n")
        (source / "untouched.txt").write_bytes(b"unchanged")
        self.lock = {"commit": module.COMMIT, "files": {
            module.FIXTURE: module.digest(fixture.read_bytes()),
            "untouched.txt": module.digest(b"unchanged")}}
        self.write_lock()
        self.output = self.root / "output"

    def write_lock(self):
        (self.root / "vendor/LOCK.json").write_text(json.dumps({"conformance": self.lock}))

    def test_localized_change_and_original_preserved(self):
        original = (self.root / "vendor/conformance" / module.FIXTURE).read_bytes()
        manifest = module.prepare(self.output, root=self.root)
        self.assertEqual((self.output / module.FIXTURE).read_bytes(), b"before\n" + module.NEW + b"\nafter\n")
        self.assertEqual((self.root / "vendor/conformance" / module.FIXTURE).read_bytes(), original)
        self.assertEqual((self.output / "untouched.txt").read_bytes(), b"unchanged")
        self.assertEqual(list(manifest["changed_files"]), [module.FIXTURE])
        self.assertFalse((self.output / "node_modules").exists())

    def test_hash_drift_rejected_before_output(self):
        (self.root / "vendor/conformance/untouched.txt").write_text("drift")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            module.prepare(self.output, root=self.root)
        self.assertFalse(self.output.exists())

    def test_unknown_pin_rejected(self):
        self.lock["commit"] = "another revision"
        self.write_lock()
        with self.assertRaisesRegex(ValueError, "reviewed upstream commit"):
            module.prepare(self.output, root=self.root)
        self.assertFalse(self.output.exists())

    def test_existing_output_preserved(self):
        self.output.mkdir()
        (self.output / "user-file").write_text("keep")
        with self.assertRaisesRegex(ValueError, "already exists"):
            module.prepare(self.output, root=self.root)
        self.assertEqual((self.output / "user-file").read_text(), "keep")

    def test_ambiguous_or_missing_patch_rejected(self):
        for data in (b"absent", module.OLD + module.OLD, module.NEW):
            with self.assertRaisesRegex(ValueError, "uniquely"):
                module.repair(data)

    def test_invalid_dependency_directory_rejected(self):
        with self.assertRaises(ValueError):
            module.prepare(self.output, self.root, root=self.root)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
