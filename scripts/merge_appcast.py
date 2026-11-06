#!/usr/bin/env python3
"""Prepend a newly signed Sparkle appcast item and keep older items.

generate_appcast rewrites every enclosure onto one download-url prefix.
GitHub Release assets live on the tag that uploaded them, so older items
must keep the URLs they already have. This script copies those items onto
the new feed without changing them.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ITEM_RE = re.compile(r"<item\b.*?</item>", re.DOTALL)
VERSION_RE = re.compile(r"<sparkle:version>\s*([^<]+?)\s*</sparkle:version>")


def items(text: str) -> list[str]:
    return ITEM_RE.findall(text)


def version_of(item: str) -> str | None:
    match = VERSION_RE.search(item)
    if match is None:
        return None
    return match.group(1).strip()


def merge(new_xml: str, old_xml: str | None) -> str:
    new_items = items(new_xml)
    if not new_items:
        raise SystemExit("新的 appcast 里没有 <item>")
    if "</channel>" not in new_xml:
        raise SystemExit("新的 appcast 里没有 </channel>")

    seen = {version for item in new_items if (version := version_of(item))}
    kept: list[str] = []
    if old_xml:
        for item in items(old_xml):
            version = version_of(item)
            if version is None or version in seen:
                continue
            seen.add(version)
            kept.append(item)

    if not kept:
        return new_xml

    insertion = "\n".join(kept) + "\n"
    return new_xml.replace("</channel>", insertion + "</channel>", 1)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("用法: merge_appcast.py NEW.xml OLD.xml OUTPUT.xml")
    new_path, old_path, output_path = map(Path, sys.argv[1:])
    old_xml = old_path.read_text(encoding="utf-8") if old_path.is_file() else None
    merged = merge(new_path.read_text(encoding="utf-8"), old_xml)
    output_path.write_text(merged, encoding="utf-8")


if __name__ == "__main__":
    main()
