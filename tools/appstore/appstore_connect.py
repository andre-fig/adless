#!/usr/bin/env python3
"""Small App Store Connect API client used by the iOS release workflow.

The release workflow intentionally keeps the Apple API integration here instead
of adding a third-party dependency to the repository. The script only handles
release orchestration: it never reads or changes app metadata or subscription
pricing.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


API_ROOT = "https://api.appstoreconnect.apple.com"
JWT_AUDIENCE = "appstoreconnect-v1"
JWT_LIFETIME_SECONDS = 15 * 60
POLL_INTERVAL_SECONDS = 30
POLL_ATTEMPTS = 40

RELEASEABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
    "METADATA_REJECTED",
}

SAFE_SKIP_STATES = {
    "READY_FOR_REVIEW",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_DEVELOPER_RELEASE",
    "PENDING_APPLE_RELEASE",
    "READY_FOR_SALE",
    "DEVELOPER_REMOVED_FROM_SALE",
    "PROCESSING_FOR_APP_STORE",
}


class APIError(RuntimeError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


def _b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    offset += 1
    if first & 0x80 == 0:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 4:
        raise ValueError("invalid DER length")
    end = offset + count
    if end > len(data):
        raise ValueError("truncated DER length")
    return int.from_bytes(data[offset:end], "big"), end


def _der_integer(data: bytes, offset: int) -> tuple[bytes, int]:
    if offset >= len(data) or data[offset] != 0x02:
        raise ValueError("invalid DER integer")
    length, value_offset = _der_length(data, offset + 1)
    end = value_offset + length
    if end > len(data):
        raise ValueError("truncated DER integer")
    return data[value_offset:end], end


def _der_signature_to_jwt_signature(signature: bytes) -> bytes:
    """Convert OpenSSL's DER ECDSA signature to JWT's r||s representation."""

    if not signature or signature[0] != 0x30:
        raise ValueError("OpenSSL did not return a DER ECDSA signature")
    _, offset = _der_length(signature, 1)
    r, offset = _der_integer(signature, offset)
    s, offset = _der_integer(signature, offset)
    if offset != len(signature):
        raise ValueError("unexpected data after DER ECDSA signature")
    return r.lstrip(b"\x00").rjust(32, b"\x00") + s.lstrip(b"\x00").rjust(32, b"\x00")


def make_token(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + JWT_LIFETIME_SECONDS,
        "aud": JWT_AUDIENCE,
    }
    unsigned = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}.{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=unsigned.encode("ascii"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"could not sign App Store Connect token: {result.stderr.decode(errors='replace').strip()}")
    signature = _der_signature_to_jwt_signature(result.stdout)
    return f"{unsigned}.{_b64url(signature)}"


class Client:
    def __init__(self, key_id: str, issuer_id: str, key_path: Path) -> None:
        self.token = make_token(key_id, issuer_id, key_path)

    def request(self, method: str, path_or_url: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
        url = path_or_url if path_or_url.startswith("http") else API_ROOT + path_or_url
        request = urllib.request.Request(
            url,
            method=method,
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
            data=json.dumps(body).encode("utf-8") if body is not None else None,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise APIError(error.code, f"App Store Connect API {error.code}: {detail[:1000]}") from error
        if not raw:
            return {}
        return json.loads(raw)

    def all_resources(self, path: str) -> list[dict[str, Any]]:
        resources: list[dict[str, Any]] = []
        next_url: str | None = path
        while next_url:
            page = self.request("GET", next_url)
            resources.extend(page.get("data", []))
            next_url = page.get("links", {}).get("next")
        return resources


def _attributes(resource: dict[str, Any]) -> dict[str, Any]:
    return resource.get("attributes", {})


def app_store_version(client: Client, app_id: str, version_string: str) -> dict[str, Any] | None:
    resources = client.all_resources(f"/v1/apps/{urllib.parse.quote(app_id)}/appStoreVersions?limit=200")
    for resource in resources:
        attrs = _attributes(resource)
        if attrs.get("platform") == "IOS" and attrs.get("versionString") == version_string:
            return resource
    return None


def app_builds(client: Client, app_id: str) -> list[dict[str, Any]]:
    quoted_id = urllib.parse.quote(app_id)
    return client.all_resources(f"/v1/apps/{quoted_id}/builds?limit=200")


def write_output(values: dict[str, str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def command_preflight(client: Client, args: argparse.Namespace) -> None:
    version = app_store_version(client, args.app_id, args.version)
    if version is None:
        raise RuntimeError(
            f"App Store version {args.version} does not exist in App Store Connect. "
            "Create and prepare the version there before pushing to main."
        )
    state = _attributes(version).get("appStoreState", "UNKNOWN")
    version_id = version["id"]
    if state in RELEASEABLE_STATES:
        should_release = "true"
        message = f"App Store version {args.version} is {state}; release may continue."
    elif state in SAFE_SKIP_STATES:
        should_release = "false"
        message = f"App Store version {args.version} is already {state}; no new submission will be created."
    else:
        raise RuntimeError(
            f"App Store version {args.version} has unsupported state {state}. "
            "Resolve it in App Store Connect before releasing."
        )
    print(message)
    write_output(
        {
            "should_release": should_release,
            "version_id": version_id,
            "version_state": state,
            "message": message,
        }
    )


def command_next_build(client: Client, args: argparse.Namespace) -> None:
    highest = 0
    for resource in app_builds(client, args.app_id):
        raw_version = _attributes(resource).get("version")
        try:
            highest = max(highest, int(str(raw_version)))
        except (TypeError, ValueError):
            continue
    next_build = max(highest + 1, args.minimum)
    print(next_build)
    write_output({"build_number": str(next_build)})


def command_wait_build(client: Client, args: argparse.Namespace) -> None:
    for attempt in range(1, POLL_ATTEMPTS + 1):
        matches = [
            resource
            for resource in app_builds(client, args.app_id)
            if str(_attributes(resource).get("version")) == str(args.build_number)
        ]
        if matches:
            matches.sort(key=lambda resource: _attributes(resource).get("uploadedDate", ""), reverse=True)
            build = matches[0]
            attrs = _attributes(build)
            processing_state = attrs.get("processingState", "UNKNOWN")
            print(f"Build {args.build_number}: {processing_state} (poll {attempt}/{POLL_ATTEMPTS})")
            if processing_state == "VALID":
                write_output({"build_id": build["id"], "processing_state": processing_state})
                return
            if processing_state == "INVALID":
                raise RuntimeError(f"Apple rejected build {args.build_number} during processing: {attrs}")
        else:
            print(f"Build {args.build_number}: not visible yet (poll {attempt}/{POLL_ATTEMPTS})")
        time.sleep(POLL_INTERVAL_SECONDS)
    raise RuntimeError(f"Timed out waiting for build {args.build_number} to become VALID")


def command_add_beta_build(client: Client, args: argparse.Namespace) -> None:
    group_path = f"/v1/betaGroups/{urllib.parse.quote(args.group_id)}/builds?limit=200"
    assigned_builds = client.all_resources(group_path)
    if any(resource.get("id") == args.build_id for resource in assigned_builds):
        print(f"Build {args.build_id} is already assigned to beta group {args.group_id}")
        return

    client.request(
        "POST",
        f"/v1/betaGroups/{urllib.parse.quote(args.group_id)}/relationships/builds",
        {"data": [{"type": "builds", "id": args.build_id}]},
    )
    print(f"Assigned build {args.build_id} to beta group {args.group_id}")


def _review_submission(client: Client, app_id: str) -> dict[str, Any]:
    body = {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    return client.request("POST", "/v1/reviewSubmissions", body)["data"]


def command_attach_submit(client: Client, args: argparse.Namespace) -> None:
    version = app_store_version(client, args.app_id, args.version)
    if version is None:
        raise RuntimeError(f"App Store version {args.version} disappeared while releasing")
    version_id = version["id"]
    state = _attributes(version).get("appStoreState")
    if state in SAFE_SKIP_STATES:
        print(f"App Store version {args.version} became {state}; stopping without a second submission")
        return

    client.request(
        "PATCH",
        f"/v1/appStoreVersions/{urllib.parse.quote(version_id)}/relationships/build",
        {"data": {"type": "builds", "id": args.build_id}},
    )
    print(f"Linked build {args.build_id} to App Store version {version_id}")

    try:
        submission = _review_submission(client, args.app_id)
    except APIError as error:
        raise RuntimeError(
            f"Could not create the review submission ({error.status}). "
            "The build was uploaded and linked; finish the submission in App Store Connect."
        ) from error
    submission_id = submission["id"]
    client.request(
        "POST",
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        },
    )
    client.request(
        "PATCH",
        f"/v1/reviewSubmissions/{urllib.parse.quote(submission_id)}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    print(f"Review submission {submission_id} submitted for App Store version {args.version}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-path", required=True, type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)

    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("--app-id", required=True)
    preflight.add_argument("--version", required=True)

    next_build = subparsers.add_parser("next-build")
    next_build.add_argument("--app-id", required=True)
    next_build.add_argument("--minimum", required=True, type=int)

    wait_build = subparsers.add_parser("wait-build")
    wait_build.add_argument("--app-id", required=True)
    wait_build.add_argument("--build-number", required=True)

    add_beta_build = subparsers.add_parser("add-beta-build")
    add_beta_build.add_argument("--group-id", required=True)
    add_beta_build.add_argument("--build-id", required=True)

    attach = subparsers.add_parser("attach-submit")
    attach.add_argument("--app-id", required=True)
    attach.add_argument("--version", required=True)
    attach.add_argument("--build-id", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        client = Client(args.key_id, args.issuer_id, args.key_path)
        if args.command == "preflight":
            command_preflight(client, args)
        elif args.command == "next-build":
            command_next_build(client, args)
        elif args.command == "wait-build":
            command_wait_build(client, args)
        elif args.command == "add-beta-build":
            command_add_beta_build(client, args)
        elif args.command == "attach-submit":
            command_attach_submit(client, args)
        else:
            raise RuntimeError(f"unsupported command: {args.command}")
    except (APIError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
