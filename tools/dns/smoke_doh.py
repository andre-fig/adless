#!/usr/bin/env python3
"""Optional live smoke test for the configured DNS-over-HTTPS endpoints."""

from __future__ import annotations

import argparse
import struct
import subprocess
import tempfile
from pathlib import Path


ENDPOINTS = {
    "cloudflare": "https://cloudflare-dns.com/dns-query",
    "quad9": "https://dns.quad9.net/dns-query",
}


def query_wire(transaction_id: int = 0xA551) -> bytes:
    header = struct.pack(">HHHHHH", transaction_id, 0x0100, 1, 0, 0, 0)
    question = b"".join(
        bytes([len(label)]) + label.encode("ascii") for label in "example.com".split(".")
    )
    return header + question + b"\x00" + struct.pack(">HH", 1, 1)


def validate_response(query: bytes, response: bytes) -> None:
    if len(response) < 12:
        raise RuntimeError("response is shorter than a DNS header")
    query_id, query_flags, query_questions = struct.unpack(">HHH", query[:6])
    response_id, response_flags, response_questions = struct.unpack(">HHH", response[:6])
    if response_id != query_id:
        raise RuntimeError("response transaction ID does not match the query")
    if not response_flags & 0x8000:
        raise RuntimeError("response does not have the DNS response flag")
    if response_questions != query_questions:
        raise RuntimeError("response question count does not match the query")
    del query_flags


def check(name: str, url: str) -> None:
    query = query_wire()
    with tempfile.TemporaryDirectory(prefix="adless-doh-") as directory:
        root = Path(directory)
        query_path = root / "query.bin"
        response_path = root / "response.bin"
        headers_path = root / "headers.txt"
        query_path.write_bytes(query)
        result = subprocess.run(
            [
                "curl",
                "--silent",
                "--show-error",
                "--fail-with-body",
                "--http2",
                "--max-time",
                "5",
                "--dump-header",
                str(headers_path),
                "--output",
                str(response_path),
                "--header",
                "Accept: application/dns-message",
                "--header",
                "Content-Type: application/dns-message",
                "--data-binary",
                f"@{query_path}",
                url,
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or "curl failed"
            raise RuntimeError(detail)

        header_lines = headers_path.read_text(encoding="ascii").splitlines()
        status_lines = [line for line in header_lines if line.startswith("HTTP/")]
        if not status_lines:
            raise RuntimeError("no HTTP status in response")
        status = int(status_lines[-1].split()[1])
        content_types = [
            line.split(":", 1)[1].strip().split(";", 1)[0].lower()
            for line in header_lines
            if line.lower().startswith("content-type:")
        ]
        body = response_path.read_bytes()
        if status < 200 or status >= 300:
            raise RuntimeError(f"HTTP status {status}")
        if not content_types or content_types[-1] != "application/dns-message":
            raise RuntimeError("unexpected content type")
        if len(body) > 64 * 1024:
            raise RuntimeError("response exceeds the configured size limit")
        validate_response(query, body)
        print(f"{name}: OK (HTTP {status}, {len(body)} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--endpoint",
        choices=["cloudflare", "quad9"],
        help="check only one endpoint (default: both)",
    )
    args = parser.parse_args()
    endpoints = {args.endpoint: ENDPOINTS[args.endpoint]} if args.endpoint else ENDPOINTS

    failures = 0
    for name, url in endpoints.items():
        try:
            check(name, url)
        except RuntimeError as error:
            failures += 1
            print(f"{name}: FAILED ({error})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
