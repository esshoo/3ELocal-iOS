#!/usr/bin/env python3
"""Sign and package a 3E Web app with Ed25519.

Usage:
  python 3eweb_sign.py INPUT_DIR_OR_3EWEB OUTPUT.3eweb \
      --private-key publisher-private-key.pem \
      --publisher-id com.essam.3e \
      --publisher-name "3E / Essam" \
      --key-id 3e-main-2026-01
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import shutil
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

SIGNATURE_NAME = "signature.json"
CHECKSUMS_NAME = "checksums.json"


def canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_input(input_path: Path, work: Path) -> Path:
    if input_path.is_dir():
        target = work / "package"
        shutil.copytree(input_path, target)
        return target
    if input_path.suffix.lower() not in {".3eweb", ".zip"}:
        raise SystemExit("Input must be a directory, .3eweb, or .zip file.")
    target = work / "package"
    target.mkdir()
    with zipfile.ZipFile(input_path) as archive:
        archive.extractall(target)
    if not (target / "manifest.json").exists():
        children = [item for item in target.iterdir() if item.is_dir()]
        if len(children) == 1 and (children[0] / "manifest.json").exists():
            return children[0]
    return target


def safe_files(package_root: Path) -> list[Path]:
    result: list[Path] = []
    for file in package_root.rglob("*"):
        if file.is_symlink():
            raise SystemExit(f"Symbolic links are not allowed: {file}")
        if not file.is_file():
            continue
        rel = file.relative_to(package_root).as_posix()
        if rel in {SIGNATURE_NAME, CHECKSUMS_NAME}:
            continue
        result.append(file)
    return sorted(result, key=lambda item: item.relative_to(package_root).as_posix())


def write_zip(package_root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in sorted(package_root.rglob("*")):
            if file.is_file():
                archive.write(file, file.relative_to(package_root).as_posix())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--private-key", required=True)
    parser.add_argument("--publisher-id", required=True)
    parser.add_argument("--publisher-name", required=True)
    parser.add_argument("--key-id", required=True)
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output = Path(args.output).resolve()
    private_key_path = Path(args.private_key).resolve()

    private_key = serialization.load_pem_private_key(private_key_path.read_bytes(), password=None)
    if not isinstance(private_key, Ed25519PrivateKey):
        raise SystemExit("The private key is not an Ed25519 key.")

    with tempfile.TemporaryDirectory(prefix="3eweb-sign-") as temp:
        package_root = load_input(input_path, Path(temp))
        manifest_path = package_root / "manifest.json"
        if not manifest_path.exists():
            raise SystemExit("manifest.json is missing.")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

        for name in (SIGNATURE_NAME, CHECKSUMS_NAME):
            candidate = package_root / name
            if candidate.exists():
                candidate.unlink()

        files = [
            {
                "path": file.relative_to(package_root).as_posix(),
                "sha256": sha256_file(file),
            }
            for file in safe_files(package_root)
        ]
        checksums = {
            "schemaVersion": 1,
            "appID": manifest["id"],
            "version": manifest["version"],
            "files": files,
        }
        checksums_data = canonical_json(checksums)
        (package_root / CHECKSUMS_NAME).write_bytes(checksums_data)

        signature = private_key.sign(checksums_data)
        signature_document = {
            "schemaVersion": 1,
            "algorithm": "Ed25519",
            "publisherID": args.publisher_id,
            "publisherName": args.publisher_name,
            "keyID": args.key_id,
            "signedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "checksumsFile": CHECKSUMS_NAME,
            "signature": base64.b64encode(signature).decode("ascii"),
        }
        (package_root / SIGNATURE_NAME).write_text(
            json.dumps(signature_document, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        write_zip(package_root, output)
        print(output)


if __name__ == "__main__":
    main()
