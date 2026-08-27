#!/usr/bin/env python3
"""Generate and validate the static Adless blocklist artifacts.

The generator intentionally uses only Python's standard library so the daily
GitHub Actions job has no third-party runtime dependency.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import ipaddress
import json
import os
import re
import shutil
import sys
import tempfile
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = Path(__file__).with_name("sources.json")
DEFAULT_ALLOWLIST = Path(__file__).with_name("allowlist.txt")
DEFAULT_OUTPUT = REPO_ROOT / "apps/landing-page/public/blocklists"
DEFAULT_WORKER_OUTPUT = REPO_ROOT / "apps/dns-worker/data/blocklist.txt"
ARTIFACT_NAMES = ("manifest.json", "blocklist.txt", "blocklist.txt.gz", "blocklist.sha256")
DOMAIN_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
ADBLOCK_DOMAIN_RULE = re.compile(r"^\|\|([^\^$\s/|]+)\^$")
RESERVED_NAMES = {
    "localhost",
    "localhost.localdomain",
    "broadcasthost",
    "ip6-allnodes",
    "ip6-allrouters",
    "ip6-localhost",
}


class BlocklistError(RuntimeError):
    """Raised when a source or generated artifact cannot be trusted."""


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def _iso8601(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def load_config(path: Path = DEFAULT_CONFIG) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BlocklistError(f"Could not read source config {path}: {error}") from error

    sources = config.get("sources")
    policy = config.get("policy", {})
    if not isinstance(sources, list) or not sources:
        raise BlocklistError("sources.json must contain a non-empty sources array")
    if not isinstance(policy, dict):
        raise BlocklistError("sources.json policy must be an object")

    enabled = []
    for source in sources:
        if not isinstance(source, dict):
            raise BlocklistError("Every blocklist source must be an object")
        required = ("id", "name", "url", "format", "enabled")
        if any(key not in source for key in required):
            raise BlocklistError(f"Blocklist source is missing one of {required}: {source}")
        if source["enabled"]:
            enabled.append(source)
    if not enabled:
        raise BlocklistError("At least one blocklist source must be enabled")
    return enabled, policy


def _is_ip_literal(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return False
    return True


def normalize_domain(value: str) -> str | None:
    """Return an ASCII lower-case DNS hostname or None for an invalid value."""

    candidate = value.strip().strip("\ufeff")
    candidate = candidate.translate(str.maketrans({"\u3002": ".", "\uff0e": ".", "\uff61": "."}))
    if candidate.endswith("."):
        candidate = candidate[:-1]
    if not candidate or candidate.endswith(".") or candidate.startswith("."):
        return None
    labels: list[str] = []
    for raw_label in candidate.split("."):
        label = unicodedata.normalize("NFKC", raw_label).lower()
        if not label:
            return None
        if any(character in label for character in ("*", "/", "|", "^", "$", ":", "@", " ", "\t", "#", "?")):
            return None
        if all(ord(character) < 128 for character in label):
            labels.append(label)
            continue
        try:
            labels.append("xn--" + label.encode("punycode").decode("ascii"))
        except UnicodeError:
            return None

    candidate = ".".join(labels)
    if not candidate or candidate in RESERVED_NAMES or _is_ip_literal(candidate):
        return None

    if len(candidate) > 253 or "." not in candidate or ".." in candidate:
        return None
    labels = candidate.split(".")
    if any(not label or len(label) > 63 or DOMAIN_PATTERN.fullmatch(label) is None for label in labels):
        return None
    return candidate


def _looks_like_error_page(data: bytes, content_type: str | None = None) -> bool:
    if content_type:
        normalized_type = content_type.lower().split(";", 1)[0].strip()
        if normalized_type in {"text/html", "application/xhtml+xml", "application/json"}:
            return True
    sample = data.lstrip()[:512].lower()
    return sample.startswith((b"<!doctype html", b"<html", b"<?xml")) or sample.startswith(b"{")


def download_https(url: str, *, timeout: int, maximum_bytes: int) -> bytes:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise BlocklistError(f"Only HTTPS sources are allowed: {url}")

    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/plain, text/*;q=0.9, */*;q=0.1",
            "User-Agent": "AdlessBlocklistGenerator/1.0 (+https://andre-fig.github.io/adless/)",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            final_url = urllib.parse.urlparse(response.geturl())
            if final_url.scheme != "https":
                raise BlocklistError(f"HTTPS source redirected to a non-HTTPS URL: {url}")
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > maximum_bytes:
                raise BlocklistError(f"Source exceeds the {maximum_bytes}-byte limit: {url}")

            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = response.read(1024 * 128)
                if not chunk:
                    break
                total += len(chunk)
                if total > maximum_bytes:
                    raise BlocklistError(f"Source exceeds the {maximum_bytes}-byte limit: {url}")
                chunks.append(chunk)
            data = b"".join(chunks)
            if not data:
                raise BlocklistError(f"Source returned an empty response: {url}")
            if _looks_like_error_page(data, response.headers.get("Content-Type")):
                raise BlocklistError(f"Source returned an HTML/JSON error page: {url}")
            return data
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        raise BlocklistError(f"Could not download {url}: {error}") from error


def _candidate_from_line(line: str, format_name: str) -> str | None:
    if line.startswith("||"):
        match = ADBLOCK_DOMAIN_RULE.fullmatch(line)
        if not match:
            raise BlocklistError(f"Unsupported executable Adblock rule: {line[:120]}")
        return match.group(1)

    if format_name == "adblock":
        if normalize_domain(line) is not None:
            return line
        raise BlocklistError(f"Unsupported Adblock rule: {line[:120]}")

    without_comment = line.split("#", 1)[0].strip()
    if not without_comment:
        return None
    tokens = re.split(r"\s+", without_comment)
    if len(tokens) == 1:
        return tokens[0]
    if len(tokens) >= 2 and _is_ip_literal(tokens[0]):
        return tokens[1]
    raise BlocklistError(f"Unsupported blocklist line: {line[:120]}")


def parse_domains(content: str | bytes, *, format_name: str = "auto", source_id: str = "source") -> set[str]:
    if isinstance(content, bytes):
        try:
            content = content.decode("utf-8-sig")
        except UnicodeDecodeError as error:
            raise BlocklistError(f"{source_id} is not valid UTF-8") from error

    domains: set[str] = set()
    for line_number, raw_line in enumerate(content.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(("!", "#", "[")):
            continue
        try:
            candidate = _candidate_from_line(line, format_name)
        except BlocklistError as error:
            raise BlocklistError(f"{source_id}:{line_number}: {error}") from error
        if candidate is None:
            continue
        normalized = normalize_domain(candidate)
        if normalized is None:
            # Hosts files commonly contain localhost and broadcast records.
            # They are intentionally not blockable entries, so discard them
            # while still rejecting other malformed source content.
            if candidate.strip().lower().rstrip(".") in RESERVED_NAMES or _is_ip_literal(candidate.strip()):
                continue
            raise BlocklistError(f"{source_id}:{line_number}: invalid domain {candidate!r}")
        domains.add(normalized)
    if not domains:
        raise BlocklistError(f"{source_id} produced no valid domains")
    return domains


def load_allowlist(path: Path) -> set[str]:
    if not path.exists():
        return set()
    domains: set[str] = set()
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        normalized = normalize_domain(line)
        if normalized is None:
            raise BlocklistError(f"allowlist.txt:{line_number}: invalid domain {line!r}")
        domains.add(normalized)
    return domains


def apply_allowlist(domains: Iterable[str], allowlist: set[str]) -> set[str]:
    if not allowlist:
        return set(domains)
    return {
        domain
        for domain in domains
        if not any(domain == allowed or domain.endswith(f".{allowed}") for allowed in allowlist)
    }


def canonical_text(domains: Iterable[str]) -> bytes:
    ordered = sorted(set(domains))
    if not ordered:
        raise BlocklistError("The generated blocklist is empty")
    return ("\n".join(ordered) + "\n").encode("utf-8")


def deterministic_gzip(data: bytes) -> bytes:
    import io

    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", compresslevel=9, mtime=0, filename="") as stream:
        stream.write(data)
    return output.getvalue()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_previous_domains(output_dir: Path) -> set[str] | None:
    previous = output_dir / "blocklist.txt"
    if not previous.exists():
        return None
    try:
        text = previous.read_text(encoding="utf-8")
    except OSError as error:
        raise BlocklistError(f"Could not read the previously published blocklist: {error}") from error
    return set(validate_canonical_text(text))


def validate_canonical_text(text: str) -> list[str]:
    if not text or not text.endswith("\n"):
        raise BlocklistError("Canonical blocklist must be non-empty and end with a newline")
    lines = text.splitlines()
    if not lines or lines != sorted(lines) or len(lines) != len(set(lines)):
        raise BlocklistError("Canonical blocklist must be sorted and deduplicated")
    for line in lines:
        if normalize_domain(line) != line:
            raise BlocklistError(f"Invalid canonical blocklist entry: {line!r}")
    return lines


def validate_artifacts(output_dir: Path) -> dict[str, Any]:
    missing = [name for name in ARTIFACT_NAMES if not (output_dir / name).is_file()]
    if missing:
        raise BlocklistError(f"Missing generated artifact(s): {', '.join(missing)}")

    try:
        manifest = json.loads((output_dir / "manifest.json").read_text(encoding="utf-8"))
        canonical = (output_dir / "blocklist.txt").read_bytes()
        compressed = (output_dir / "blocklist.txt.gz").read_bytes()
        checksum_file = (output_dir / "blocklist.sha256").read_text(encoding="utf-8")
    except (OSError, json.JSONDecodeError) as error:
        raise BlocklistError(f"Could not read generated artifacts: {error}") from error

    if not isinstance(manifest, dict):
        raise BlocklistError("Generated manifest must be an object")

    try:
        canonical_text_value = canonical.decode("utf-8")
        domains = validate_canonical_text(canonical_text_value)
        decompressed = gzip.decompress(compressed)
    except (UnicodeDecodeError, OSError, EOFError, gzip.BadGzipFile) as error:
        raise BlocklistError(f"Generated gzip/canonical payload is invalid: {error}") from error

    compressed_hash = sha256_hex(compressed)
    if decompressed != canonical:
        raise BlocklistError("blocklist.txt.gz does not decompress to blocklist.txt")
    if manifest.get("schemaVersion") != 1:
        raise BlocklistError("Unsupported blocklist manifest schema")
    if manifest.get("file") != "blocklist.txt.gz" or manifest.get("compression") != "gzip":
        raise BlocklistError("Manifest points to an unsupported blocklist artifact")
    if manifest.get("downloadUrl") != "blocklist.txt.gz":
        raise BlocklistError("Manifest must publish the relative blocklist URL")
    if manifest.get("sha256") != compressed_hash:
        raise BlocklistError("Manifest SHA-256 does not match blocklist.txt.gz")
    if manifest.get("sizeBytes") != len(compressed) or manifest.get("uncompressedSizeBytes") != len(canonical):
        raise BlocklistError("Manifest file sizes do not match the generated artifacts")
    if manifest.get("domainCount") != len(domains):
        raise BlocklistError("Manifest domainCount does not match blocklist.txt")
    if not re.fullmatch(r"v[0-9a-f]{16}", str(manifest.get("version", ""))):
        raise BlocklistError("Manifest version must be content-derived")
    if not re.fullmatch(r"[0-9a-f]{64}  blocklist\.txt\.gz\n", checksum_file):
        raise BlocklistError("blocklist.sha256 has an invalid format")
    if checksum_file.split()[0] != compressed_hash:
        raise BlocklistError("blocklist.sha256 does not match blocklist.txt.gz")
    return manifest


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _atomic_write(path: Path, data: bytes) -> None:
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


def generate(
    *,
    config_path: Path = DEFAULT_CONFIG,
    allowlist_path: Path = DEFAULT_ALLOWLIST,
    output_dir: Path = DEFAULT_OUTPUT,
    worker_path: Path = DEFAULT_WORKER_OUTPUT,
    timeout: int = 30,
    allow_large_change: bool = False,
    sync_worker: bool = False,
) -> dict[str, Any]:
    sources, policy = load_config(config_path)
    maximum_source_bytes = int(policy.get("maximumSourceBytes", 25_000_000))
    minimum_source_bytes = int(policy.get("minimumSourceBytes", 1_000))
    all_domains: set[str] = set()
    source_summaries: list[dict[str, str]] = []

    for source in sources:
        raw = download_https(source["url"], timeout=timeout, maximum_bytes=maximum_source_bytes)
        if len(raw) < minimum_source_bytes:
            raise BlocklistError(f"{source['id']} source is suspiciously small: {len(raw)} bytes")
        source_domains = parse_domains(raw, format_name=source["format"], source_id=source["id"])
        all_domains.update(source_domains)
        source_summaries.append({"id": source["id"], "name": source["name"]})

    domains = apply_allowlist(all_domains, load_allowlist(allowlist_path))
    minimum_domains = int(policy.get("minimumDomainCount", 1))
    maximum_domains = int(policy.get("maximumDomainCount", 200_000))
    if len(domains) < minimum_domains or len(domains) > maximum_domains:
        raise BlocklistError(
            f"Generated domain count {len(domains)} is outside the allowed range "
            f"[{minimum_domains}, {maximum_domains}]"
        )

    canonical = canonical_text(domains)
    compressed = deterministic_gzip(canonical)
    compressed_hash = sha256_hex(compressed)
    content_hash = sha256_hex(canonical)

    previous_domains = _read_previous_domains(output_dir)
    if previous_domains is not None:
        changed_domains = len(domains.symmetric_difference(previous_domains))
        change_ratio = changed_domains / max(len(previous_domains), 1)
        maximum_change_ratio = float(policy.get("maximumChangeRatio", 0.35))
        if change_ratio > maximum_change_ratio and not allow_large_change:
            raise BlocklistError(
                f"Domain set changed by {change_ratio:.1%}, above the {maximum_change_ratio:.1%} limit; "
                "rerun with --allow-large-change only after manual review"
            )

    previous_manifest: dict[str, Any] | None = None
    previous_manifest_path = output_dir / "manifest.json"
    if previous_manifest_path.exists():
        try:
            previous_manifest = json.loads(previous_manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            previous_manifest = None
    generated_at = _iso8601(_utc_now())
    if previous_manifest and previous_manifest.get("sha256") == compressed_hash:
        generated_at = str(previous_manifest.get("generatedAt", generated_at))

    manifest: dict[str, Any] = {
        "schemaVersion": 1,
        "version": f"v{content_hash[:16]}",
        "generatedAt": generated_at,
        "file": "blocklist.txt.gz",
        "downloadUrl": "blocklist.txt.gz",
        "compression": "gzip",
        "sha256": compressed_hash,
        "sizeBytes": len(compressed),
        "uncompressedSizeBytes": len(canonical),
        "domainCount": len(domains),
        "sources": source_summaries,
    }

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    candidate_dir = Path(tempfile.mkdtemp(prefix=".blocklist-candidate-", dir=output_dir.parent))
    try:
        (candidate_dir / "blocklist.txt").write_bytes(canonical)
        (candidate_dir / "blocklist.txt.gz").write_bytes(compressed)
        (candidate_dir / "blocklist.sha256").write_text(f"{compressed_hash}  blocklist.txt.gz\n", encoding="utf-8")
        _write_json(candidate_dir / "manifest.json", manifest)
        validate_artifacts(candidate_dir)

        output_dir.mkdir(parents=True, exist_ok=True)
        for name in ARTIFACT_NAMES:
            os.replace(candidate_dir / name, output_dir / name)

        if sync_worker:
            _atomic_write(worker_path, canonical)
    finally:
        shutil.rmtree(candidate_dir, ignore_errors=True)

    return manifest


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--allowlist", type=Path, default=DEFAULT_ALLOWLIST)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--worker-output", type=Path, default=DEFAULT_WORKER_OUTPUT)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--allow-large-change", action="store_true")
    parser.add_argument("--sync-worker", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        manifest = generate(
            config_path=args.config,
            allowlist_path=args.allowlist,
            output_dir=args.output_dir,
            worker_path=args.worker_output,
            timeout=args.timeout,
            allow_large_change=args.allow_large_change,
            sync_worker=args.sync_worker,
        )
    except BlocklistError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"version": manifest["version"], "domainCount": manifest["domainCount"], "sha256": manifest["sha256"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
