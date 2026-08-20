#!/usr/bin/env python3
"""Validate generated Adless blocklist artifacts or an embedded seed file."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.blocklists.generate_blocklist import (  # noqa: E402
    DEFAULT_OUTPUT,
    BlocklistError,
    validate_artifacts,
    validate_canonical_text,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--seed", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.seed:
            domains = validate_canonical_text(args.seed.read_text(encoding="utf-8"))
            if len(domains) < 1:
                raise BlocklistError("Embedded seed is empty")
            print(f"valid seed: {len(domains)} domains")
        else:
            manifest = validate_artifacts(args.output_dir)
            print(f"valid artifacts: {manifest['version']} ({manifest['domainCount']} domains)")
    except (BlocklistError, OSError, UnicodeDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
