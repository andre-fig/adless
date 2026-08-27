#!/usr/bin/env python3
"""Validate generated public and edge blocklist artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.blocklists.generate_blocklist import (  # noqa: E402
    DEFAULT_OUTPUT,
    DEFAULT_WORKER_OUTPUT,
    BlocklistError,
    validate_artifacts,
    validate_canonical_text,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--worker", type=Path, default=DEFAULT_WORKER_OUTPUT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.worker:
            worker_bytes = args.worker.read_bytes()
            domains = validate_canonical_text(worker_bytes.decode("utf-8"))
            if len(domains) < 1:
                raise BlocklistError("Worker blocklist is empty")
            manifest = validate_artifacts(args.output_dir)
            if len(domains) != manifest["domainCount"]:
                raise BlocklistError("Worker blocklist count differs from the published artifact")
            metadata_path = args.worker.with_name("blocklist.meta.json")
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            if not isinstance(metadata, dict):
                raise BlocklistError("Worker metadata must be an object")
            if metadata.get("schemaVersion") != 1:
                raise BlocklistError("Worker metadata schema is invalid")
            if metadata.get("version") != manifest["version"]:
                raise BlocklistError("Worker version differs from the published artifact")
            if metadata.get("domainCount") != len(domains):
                raise BlocklistError("Worker metadata count differs from the blocklist")
            if metadata.get("textSHA256") != hashlib.sha256(worker_bytes).hexdigest():
                raise BlocklistError("Worker metadata checksum does not match the blocklist")
            if metadata.get("sourceSHA256") != manifest["sha256"]:
                raise BlocklistError("Worker source checksum differs from the published artifact")
            print(f"valid worker blocklist: {manifest['version']} ({len(domains)} domains)")
    except (BlocklistError, OSError, UnicodeDecodeError, json.JSONDecodeError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
