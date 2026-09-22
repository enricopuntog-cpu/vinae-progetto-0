#!/usr/bin/env python3
"""Security checks for the isolated offsite restore validator."""

import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("offsite-archive-validate.py")
SPEC = importlib.util.spec_from_file_location("offsite_archive_validate", SCRIPT)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class ArchiveValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.destination = Path(self.temp.name)
        self.root = self.destination / "vinea-backup"
        files = {
            "database/roles.sql": b"roles\n",
            "database/schema.sql": b"schema\n",
            "database/data.sql": b"data\n",
            "storage/example/one.txt": b"sample",
        }
        inventory = {"buckets": [{"id": "example", "objects": [{"name": "one.txt", "size": 6}]}]}
        files["storage/storage-manifest.json"] = json.dumps(inventory).encode()
        for name, content in files.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        manifest = "".join(
            f"{hashlib.sha256(content).hexdigest()}  ./{name}\n"
            for name, content in sorted(files.items())
        )
        (self.root / "MANIFEST.sha256").write_text(manifest, encoding="utf-8")
        self.archive = self.destination / "backup.tar.gz"

    def build_archive(self, extra=None):
        with tarfile.open(self.archive, "w:gz") as archive:
            archive.add(self.root, arcname="vinea-backup")
            if extra:
                extra(archive)

    def test_valid_backup(self):
        self.build_archive()
        validator.check_archive(self.archive)
        validator.check_extracted(self.destination)

    def test_rejects_path_traversal_before_extraction(self):
        def add_traversal(archive):
            member = tarfile.TarInfo("vinea-backup/../escape")
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))

        self.build_archive(add_traversal)
        with self.assertRaises(ValueError):
            validator.check_archive(self.archive)

    def test_rejects_symlink_before_extraction(self):
        def add_link(archive):
            member = tarfile.TarInfo("vinea-backup/storage/example/link")
            member.type = tarfile.SYMTYPE
            member.linkname = "../../../../escape"
            archive.addfile(member)

        self.build_archive(add_link)
        with self.assertRaises(ValueError):
            validator.check_archive(self.archive)

    def test_rejects_unlisted_file_and_tampered_manifest(self):
        unexpected = self.root / "storage/example/unlisted.txt"
        unexpected.write_bytes(b"extra")
        with self.assertRaises(ValueError):
            validator.check_extracted(self.destination)
        unexpected.unlink()
        (self.root / "database/data.sql").write_bytes(b"altered")
        with self.assertRaises(ValueError):
            validator.check_extracted(self.destination)

    def test_restore_script_decrypts_isolated_fixture(self):
        age = os.environ.get("AGE_EXE")
        bash = os.environ.get("BASH_EXE")
        cygpath = os.environ.get("CYGPATH_EXE")
        if not (age and bash and cygpath):
            self.skipTest("AGE_EXE, BASH_EXE and CYGPATH_EXE are needed for the Windows integration test")
        self.build_archive()
        identity = self.destination / "test-age.key"
        keygen = str(Path(age).with_name("age-keygen.exe"))
        subprocess.run([keygen, "-o", str(identity)], check=True, capture_output=True)
        recipient = subprocess.run([keygen, "-y", str(identity)], check=True, capture_output=True, text=True).stdout.strip()
        encrypted = self.destination / "backup.tar.gz.age"
        subprocess.run([age, "-r", recipient, "-o", str(encrypted), str(self.archive)], check=True, capture_output=True)
        encrypted.with_name(encrypted.name + ".sha256").write_text(
            f"{hashlib.sha256(encrypted.read_bytes()).hexdigest()}  {encrypted.name}\n",
            encoding="utf-8",
        )

        def cygwin(path):
            return subprocess.run([cygpath, "-u", str(path)], check=True, capture_output=True, encoding="utf-8").stdout.strip()

        destination = self.destination / "isolated"
        restore = SCRIPT.with_name("offsite-restore-verify.sh")
        result = subprocess.run(
            [bash, "-c", 'export PATH="$1:$PATH" PYTHON_BIN="$2"; shift 2; exec "$@"',
             "bash", cygwin(Path(age).parent), cygwin(sys.executable),
             cygwin(restore), cygwin(encrypted), cygwin(identity), cygwin(destination)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((destination / "vinea-backup/database/data.sql").is_file())


if __name__ == "__main__":
    unittest.main()
