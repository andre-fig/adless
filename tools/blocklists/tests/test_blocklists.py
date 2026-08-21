import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.blocklists import generate_blocklist as pipeline


class BlocklistParsingTests(unittest.TestCase):
    def test_production_seed_smoke_matrix_keeps_core_sites_reachable_and_ad_domains_blocked(self):
        entries = pipeline.parse_domains(
            pipeline.DEFAULT_SEED.read_text(encoding="utf-8"),
            source_id="embedded-seed",
        )

        expected_allowed = (
            "www.google.com",
            "web.whatsapp.com",
            "www.instagram.com",
            "www.facebook.com",
            "www.youtube.com",
        )
        expected_blocked = (
            "googlesyndication.com",
            "adsrvr.org",
            "criteo.com",
            "pubmatic.com",
            "adnxs1.com",
        )

        def matches(domain: str) -> bool:
            labels = domain.rstrip(".").lower().split(".")
            return any(".".join(labels[index:]) in entries for index in range(len(labels)))

        for domain in expected_allowed:
            self.assertFalse(matches(domain), f"Core site unexpectedly blocked: {domain}")
        for domain in expected_blocked:
            self.assertTrue(matches(domain), f"Known advertising domain unexpectedly allowed: {domain}")

    def test_parses_hosts_adblock_and_plain_domains(self):
        content = """
        ! header
        # comment
        0.0.0.0 Ads.Example.com # inline comment
        127.0.0.1 tracker.example.com
        ||cdn.example.net^
        mail.example.org.
        0.0.0.0 localhost
        192.0.2.10
        """

        domains = pipeline.parse_domains(content, format_name="auto", source_id="fixture")

        self.assertEqual(
            domains,
            {"ads.example.com", "tracker.example.com", "cdn.example.net", "mail.example.org"},
        )

    def test_idn_is_converted_to_ascii_and_duplicates_are_removed(self):
        domains = pipeline.parse_domains(
            "Bücher.Example\n xn--bcher-kva.example.\n||BÜCHER.EXAMPLE^\n",
            format_name="auto",
        )

        self.assertEqual(domains, {"xn--bcher-kva.example"})

    def test_rejects_unsupported_executable_adblock_rule(self):
        with self.assertRaises(pipeline.BlocklistError):
            pipeline.parse_domains("/tracking.js\n", format_name="adblock")

    def test_allowlist_removes_domain_and_descendants(self):
        result = pipeline.apply_allowlist(
            {"ads.example.com", "safe.example.com", "example.net"},
            {"example.com"},
        )

        self.assertEqual(result, {"example.net"})

    def test_empty_source_and_html_are_rejected(self):
        with self.assertRaises(pipeline.BlocklistError):
            pipeline.parse_domains("<!doctype html><html>error</html>", source_id="html")
        with self.assertRaises(pipeline.BlocklistError):
            pipeline.parse_domains("# no domains\n", source_id="empty")


class BlocklistArtifactTests(unittest.TestCase):
    def _config(self, directory: Path) -> Path:
        config = directory / "sources.json"
        config.write_text(
            json.dumps(
                {
                    "sources": [
                        {
                            "id": "fixture",
                            "name": "Fixture",
                            "enabled": True,
                            "url": "https://fixture.invalid/list",
                            "format": "auto",
                        }
                    ],
                    "policy": {
                        "minimumDomainCount": 1,
                        "maximumDomainCount": 100,
                        "maximumChangeRatio": 0.25,
                        "minimumSourceBytes": 1,
                    },
                }
            ),
            encoding="utf-8",
        )
        return config

    def test_gzip_is_deterministic(self):
        payload = pipeline.canonical_text({"b.example.com", "a.example.com"})
        self.assertEqual(pipeline.deterministic_gzip(payload), pipeline.deterministic_gzip(payload))

    def test_generation_is_deterministic_and_preserves_generated_at(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            output = directory / "public" / "blocklists"
            config = self._config(directory)
            allowlist = directory / "allowlist.txt"
            allowlist.write_text("# intentionally empty\n", encoding="utf-8")
            source = b"||ads.example.com^\n||tracker.example.com^\n"

            with patch.object(pipeline, "download_https", return_value=source):
                first = pipeline.generate(
                    config_path=config,
                    allowlist_path=allowlist,
                    output_dir=output,
                )
                first_manifest = (output / "manifest.json").read_bytes()
                second = pipeline.generate(
                    config_path=config,
                    allowlist_path=allowlist,
                    output_dir=output,
                )

            self.assertEqual(first["version"], second["version"])
            self.assertEqual(first["sha256"], second["sha256"])
            self.assertEqual(first_manifest, (output / "manifest.json").read_bytes())
            self.assertEqual(pipeline.validate_artifacts(output)["domainCount"], 2)

    def test_large_change_is_rejected_without_replacing_last_valid_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            output = directory / "public" / "blocklists"
            config = self._config(directory)
            allowlist = directory / "allowlist.txt"
            allowlist.write_text("", encoding="utf-8")
            original = b"||ads.example.com^\n||tracker.example.com^\n"
            changed = b"||one.example.com^\n||two.example.com^\n||three.example.com^\n"

            with patch.object(pipeline, "download_https", return_value=original):
                pipeline.generate(config_path=config, allowlist_path=allowlist, output_dir=output)
            before = (output / "blocklist.txt.gz").read_bytes()

            with patch.object(pipeline, "download_https", return_value=changed):
                with self.assertRaises(pipeline.BlocklistError):
                    pipeline.generate(config_path=config, allowlist_path=allowlist, output_dir=output)

            self.assertEqual(before, (output / "blocklist.txt.gz").read_bytes())

    def test_manifest_checksum_and_invalid_gzip_are_detected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            output = directory / "public" / "blocklists"
            config = self._config(directory)
            allowlist = directory / "allowlist.txt"
            allowlist.write_text("", encoding="utf-8")

            with patch.object(pipeline, "download_https", return_value=b"||ads.example.com^\n"):
                pipeline.generate(config_path=config, allowlist_path=allowlist, output_dir=output)
            (output / "blocklist.txt.gz").write_bytes(b"not gzip")

            with self.assertRaises(pipeline.BlocklistError):
                pipeline.validate_artifacts(output)


if __name__ == "__main__":
    unittest.main()
