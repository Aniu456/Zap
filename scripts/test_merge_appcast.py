#!/usr/bin/env python3
"""Checks for merge_appcast.py. Run from the repo root: python3 scripts/test_merge_appcast.py"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


def load_merge():
    path = Path(__file__).with_name("merge_appcast.py")
    spec = importlib.util.spec_from_file_location("merge_appcast", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


merge_appcast = load_merge()


def feed(body: str) -> str:
    return (
        '<?xml version="1.0" standalone="yes"?>\n'
        '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
        "    <channel>\n"
        "        <title>Zap</title>\n"
        f"{body}\n"
        "    </channel>\n"
        "</rss>\n"
    )


def item(version: str, url: str, hardware: str | None = None) -> str:
    requirement = ""
    if hardware is not None:
        requirement = f"            <sparkle:hardwareRequirements>{hardware}</sparkle:hardwareRequirements>\n"
    return (
        "        <item>\n"
        f"            <title>{version}</title>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"{requirement}"
        f'            <enclosure url="{url}" length="10" type="application/octet-stream" '
        'sparkle:edSignature="sig"/>\n'
        "        </item>"
    )


class MergeAppcastTests(unittest.TestCase):
    def test_combine_puts_apple_silicon_before_intel(self):
        apple = feed(item("1.0.1", "https://example.com/Zap-1.0.1-apple-silicon.zip", "arm64"))
        intel = feed(item("1.0.1", "https://example.com/Zap-1.0.1-intel.zip"))
        combined = merge_appcast.combine(apple, intel)
        apple_at = combined.index("Zap-1.0.1-apple-silicon.zip")
        intel_at = combined.index("Zap-1.0.1-intel.zip")
        self.assertLess(apple_at, intel_at)
        self.assertEqual(combined.count("<item"), 2)
        self.assertIn("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>", combined)
        intel_item = merge_appcast.items(combined)[1]
        self.assertNotIn("hardwareRequirements", intel_item)

    def test_combine_rejects_intel_marked_arm64(self):
        apple = feed(item("1.0.1", "https://example.com/a.zip", "arm64"))
        intel = feed(item("1.0.1", "https://example.com/i.zip", "arm64"))
        with self.assertRaises(SystemExit):
            merge_appcast.combine(apple, intel)

    def test_combine_rejects_apple_without_arm64_requirement(self):
        apple = feed(item("1.0.1", "https://example.com/a.zip"))
        intel = feed(item("1.0.1", "https://example.com/i.zip"))
        with self.assertRaises(SystemExit):
            merge_appcast.combine(apple, intel)

    def test_merge_keeps_older_universal_item_and_both_new_architectures(self):
        apple = feed(item("1.0.1", "https://example.com/Zap-1.0.1-apple-silicon.zip", "arm64"))
        intel = feed(item("1.0.1", "https://example.com/Zap-1.0.1-intel.zip"))
        combined = merge_appcast.combine(apple, intel)
        old = feed(item("1.0.0", "https://example.com/releases/download/v1.0.0/Zap-1.0.0.zip"))
        merged = merge_appcast.merge(combined, old)
        found = merge_appcast.items(merged)
        self.assertEqual(
            [merge_appcast.version_of(entry) for entry in found],
            ["1.0.1", "1.0.1", "1.0.0"],
        )
        self.assertIn("v1.0.0/Zap-1.0.0.zip", found[2])
        self.assertLess(merged.index("apple-silicon"), merged.index("Zap-1.0.1-intel.zip"))

    def test_cli_combine_writes_the_file(self):
        apple = feed(item("1.2.0", "https://example.com/Zap-1.2.0-apple-silicon.zip", "arm64"))
        intel = feed(item("1.2.0", "https://example.com/Zap-1.2.0-intel.zip"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apple_path = root / "apple.xml"
            intel_path = root / "intel.xml"
            output = root / "appcast.xml"
            apple_path.write_text(apple, encoding="utf-8")
            intel_path.write_text(intel, encoding="utf-8")
            import sys

            argv = sys.argv
            sys.argv = ["merge_appcast.py", "combine", str(apple_path), str(intel_path), str(output)]
            try:
                merge_appcast.main()
            finally:
                sys.argv = argv
            text = output.read_text(encoding="utf-8")
            self.assertLess(text.index("apple-silicon"), text.index("intel.zip"))


if __name__ == "__main__":
    unittest.main()
