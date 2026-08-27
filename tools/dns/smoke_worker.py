#!/usr/bin/env python3
"""Optional live smoke test for an Adless DNS Worker deployment.

The token is read from ADLESS_INSTALLATION_TOKEN and is never included in
diagnostics. The test deliberately uses only a synthetic example query.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import ssl
import struct
import urllib.error
import urllib.parse
import urllib.request


def query_wire(transaction_id: int = 0xA551) -> bytes:
    header = struct.pack(">HHHHHH", transaction_id, 0x0100, 1, 0, 0, 0)
    question = b"".join(bytes([len(label)]) + label.encode("ascii") for label in "example.com".split("."))
    return header + question + b"\x00" + struct.pack(">HH", 1, 1)


def request(url: str, *, method: str, body: bytes | None = None, token: str | None = None) -> tuple[int, dict[str, str], bytes]:
    headers = {"Accept": "application/dns-message", "User-Agent": "AdlessSmoke/1.0"}
    if body is not None:
        headers["Content-Type"] = "application/dns-message"
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, data=body, headers=headers, method=method),
            timeout=5,
            context=ssl.create_default_context(),
        ) as response:
            return response.status, {key.lower(): value for key, value in response.headers.items()}, response.read(65536)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"HTTP {error.code}") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("TLS or transport failure") from None


def validate_dns(query: bytes, response: bytes) -> None:
    if len(response) < 12 or response[:2] != query[:2] or not (response[2] & 0x80):
        raise RuntimeError("invalid DNS wire response")


def check(base_url: str, token: str) -> None:
    parsed = urllib.parse.urlparse(base_url)
    if parsed.scheme != "https" or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
        raise RuntimeError("--url must be an HTTPS origin")
    origin = base_url.rstrip("/")
    query = query_wire()
    endpoint = f"{origin}/{token}/dns-query"

    status, headers, body = request(endpoint, method="POST", body=query)
    if status < 200 or status >= 300 or headers.get("content-type", "").split(";", 1)[0] != "application/dns-message":
        raise RuntimeError("POST did not return DNS wire format")
    validate_dns(query, body)

    encoded = base64.urlsafe_b64encode(query).rstrip(b"=").decode("ascii")
    status, headers, body = request(f"{endpoint}?dns={encoded}", method="GET")
    if status < 200 or status >= 300 or headers.get("content-type", "").split(";", 1)[0] != "application/dns-message":
        raise RuntimeError("GET did not return DNS wire format")
    validate_dns(query, body)

    stats_status, stats_headers, stats_body = request(f"{origin}/v1/stats", method="GET", token=token)
    if stats_status != 200 or not stats_headers.get("content-type", "").startswith("application/json"):
        raise RuntimeError("stats endpoint is unavailable")
    payload = json.loads(stats_body)
    if not isinstance(payload.get("blockedTotal"), int) or payload["blockedTotal"] < 0 or not isinstance(payload.get("updatedAt"), str):
        raise RuntimeError("stats payload is invalid")
    print("Adless DNS Worker: POST, GET, and stats OK")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="HTTPS origin, without the token path")
    args = parser.parse_args()
    token = os.environ.get("ADLESS_INSTALLATION_TOKEN", "")
    if re.fullmatch(r"[A-Za-z0-9_-]{43}", token) is None:
        parser.error("ADLESS_INSTALLATION_TOKEN must be a 43-character Base64URL token")
    try:
        check(args.url, token)
    except (RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"Adless DNS Worker: FAILED ({error})")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
