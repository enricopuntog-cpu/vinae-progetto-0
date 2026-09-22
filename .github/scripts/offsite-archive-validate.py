#!/usr/bin/env python3
"""Validate an offsite archive before extraction and its manifest afterwards."""

import hashlib
import json
import re
import stat
import sys
import tarfile
from pathlib import Path


REQUIRED = {
    "database/roles.sql",
    "database/schema.sql",
    "database/data.sql",
    "storage/storage-manifest.json",
}
HASH_LINE = re.compile(r"^([0-9a-f]{64})  \./(.+)$")
WINDOWS_RESERVED = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(1, 10)), *(f"lpt{i}" for i in range(1, 10))}


def fail():
    raise ValueError("Archivio, inventario o MANIFEST.sha256 non valido.")


def parts_for(name):
    if not isinstance(name, str) or not name or name.startswith("/") or "\\" in name:
        fail()
    parts = name.rstrip("/").split("/")
    if any(
        not part or part in (".", "..") or ":" in part or part[-1] in (" ", ".")
        or any(ord(char) < 32 or ord(char) == 127 for char in part)
        or part.split(".", 1)[0].casefold() in WINDOWS_RESERVED
        for part in parts
    ):
        fail()
    return parts


def check_archive(path):
    seen = set()
    files = set()
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            parts = parts_for(member.name)
            if parts[0] != "vinea-backup" or not (member.isdir() or member.isfile()):
                fail()
            canonical = "/".join(parts)
            if canonical.casefold() in seen:
                fail()
            seen.add(canonical.casefold())
            if member.isfile():
                relative = "/".join(parts[1:])
                if relative not in REQUIRED | {"MANIFEST.sha256"} and not (
                    len(parts) >= 4 and parts[1] == "storage"
                ):
                    fail()
                files.add(relative)
    if not REQUIRED | {"MANIFEST.sha256"} <= files:
        fail()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def check_extracted(destination):
    root = destination / "vinea-backup"
    if not root.is_dir():
        fail()
    actual = set()
    for entry in root.rglob("*"):
        mode = entry.lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            fail()
        if stat.S_ISREG(mode):
            actual.add(entry.relative_to(root).as_posix())
    if not REQUIRED | {"MANIFEST.sha256"} <= actual:
        fail()

    inventory = json.loads((root / "storage/storage-manifest.json").read_text(encoding="utf-8"))
    if not isinstance(inventory, dict) or not isinstance(inventory.get("buckets"), list):
        fail()
    expected = REQUIRED | {"MANIFEST.sha256"}
    for bucket in inventory["buckets"]:
        if not isinstance(bucket, dict) or not isinstance(bucket.get("objects"), list):
            fail()
        bucket_id = bucket.get("id")
        if not isinstance(bucket_id, str) or len(parts_for(bucket_id)) != 1:
            fail()
        for obj in bucket["objects"]:
            if not isinstance(obj, dict) or not isinstance(obj.get("name"), str):
                fail()
            object_name = obj["name"]
            parts_for(object_name)
            relative = f"storage/{bucket_id}/{object_name}"
            if relative in expected:
                fail()
            expected.add(relative)
            size = obj.get("size")
            if type(size) is not int or size < 0 or (root / relative).stat().st_size != size:
                fail()
    if actual != expected or len({name.casefold() for name in actual}) != len(actual):
        fail()

    declared = {}
    for line in (root / "MANIFEST.sha256").read_text(encoding="utf-8").splitlines():
        match = HASH_LINE.fullmatch(line)
        if not match:
            fail()
        relative = match.group(2)
        parts_for(relative)
        if relative in declared:
            fail()
        declared[relative] = match.group(1)
    if set(declared) != actual - {"MANIFEST.sha256"}:
        fail()
    for relative, expected_hash in declared.items():
        if sha256(root / relative) != expected_hash:
            fail()


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            fail()
        if sys.argv[1] == "archive":
            check_archive(Path(sys.argv[2]))
        elif sys.argv[1] == "extracted":
            check_extracted(Path(sys.argv[2]))
        else:
            fail()
    except (OSError, ValueError, KeyError, UnicodeError, tarfile.TarError):
        print("Archivio, inventario o MANIFEST.sha256 non valido.", file=sys.stderr)
        sys.exit(1)
