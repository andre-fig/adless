#!/usr/bin/env python3
"""Copy the validated canonical blocklist into the Worker bundle atomically."""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.blocklists.generate_blocklist import DEFAULT_OUTPUT, BlocklistError, validate_artifacts, validate_canonical_text


ROOT = Path(__file__).resolve().parents[2]
WORKER_DATA = ROOT / "apps/dns-worker/data"


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main() -> int:
    try:
        manifest = validate_artifacts(DEFAULT_OUTPUT)
        canonical = (DEFAULT_OUTPUT / "blocklist.txt").read_bytes()
        domains = validate_canonical_text(canonical.decode("utf-8"))
        if not domains:
            raise BlocklistError("published blocklist is empty")
        metadata = {
            "schemaVersion": 1,
            "version": manifest["version"],
            "domainCount": len(domains),
            "textSHA256": hashlib.sha256(canonical).hexdigest(),
            "sourceSHA256": manifest["sha256"],
            "uncompressedSizeBytes": len(canonical),
        }
        atomic_write(WORKER_DATA / "blocklist.txt", canonical)
        atomic_write(WORKER_DATA / "blocklist.meta.json", (json.dumps(metadata, indent=2) + "\n").encode("utf-8"))
        print(json.dumps({"version": metadata["version"], "domainCount": metadata["domainCount"], "textSHA256": metadata["textSHA256"]}))
    except (BlocklistError, OSError, UnicodeDecodeError, KeyError) as error:
        print(f"error: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
