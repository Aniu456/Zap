#!/usr/bin/env python3
"""Merge Sparkle appcasts without rewriting enclosure URLs.

generate_appcast rewrites every enclosure onto one download-url prefix.
GitHub Release assets live on the tag that uploaded them, so older items
must keep the URLs they already have.

Sparkle 2.10.1 keys archives by CFBundleVersion alone, and rejects two
packages of that same version in one generate_appcast run. Architecture
is not an enclosure attribute. The supported split is:

- one feed per architecture, baked into that build's SUFeedURL
- sparkle:hardwareRequirements of arm64, which generate_appcast writes
  when the main executable has no Intel slice

combine() only stacks those two already-signed feeds so the legacy
universal build, which still requests appcast.xml, sees the Apple silicon
item first. Sparkle keeps the first item when versions compare equal, and
drops the arm64 item on Intel.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ITEM_RE = re.compile(r"<item\b.*?</item>", re.DOTALL)
VERSION_RE = re.compile(r"<sparkle:version>\s*([^<]+?)\s*</sparkle:version>")
HARDWARE_RE = re.compile(
    r"<sparkle:hardwareRequirements>\s*([^<]*?)\s*</sparkle:hardwareRequirements>"
)


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
    if old_xml is not None:
        root = ET.fromstring(old_xml)
        if root.tag != "rss" or root.find("./channel/item") is None:
            raise SystemExit("旧 appcast 不含有效的更新条目")
        previous_items = items(old_xml)
        if len(previous_items) != len(root.findall("./channel/item")):
            raise SystemExit("旧 appcast 条目无法完整解析")
        for item in previous_items:
            version = version_of(item)
            if version is None:
                raise SystemExit("旧 appcast 条目缺少版本号")
            if version in seen:
                continue
            seen.add(version)
            kept.append(item)

    if not kept:
        return new_xml

    insertion = "\n".join(kept) + "\n"
    return new_xml.replace("</channel>", insertion + "</channel>", 1)


def hardware_requirements(item: str) -> set[str]:
    tokens: set[str] = set()
    for value in HARDWARE_RE.findall(item):
        tokens.update(part.strip() for part in value.split(",") if part.strip())
    return tokens


def combine(apple_xml: str, intel_xml: str) -> str:
    """Place the Intel item after the Apple silicon item.

    Both documents are fresh generate_appcast output for the same version.
    The Apple silicon item must already carry sparkle:hardwareRequirements
    arm64. The Intel item must not, or Intel Macs would reject their own update.
    """
    apple_items = items(apple_xml)
    intel_items = items(intel_xml)
    if not apple_items:
        raise SystemExit("Apple 芯片的 appcast 里没有 <item>")
    if not intel_items:
        raise SystemExit("Intel 的 appcast 里没有 <item>")
    if "</channel>" not in apple_xml:
        raise SystemExit("Apple 芯片的 appcast 里没有 </channel>")
    apple_version = version_of(apple_items[0])
    intel_version = version_of(intel_items[0])
    if apple_version is None or apple_version != intel_version:
        raise SystemExit("两种架构的最新版本号不一致")
    if "arm64" not in hardware_requirements(apple_items[0]):
        raise SystemExit("Apple 芯片的 appcast 缺少 sparkle:hardwareRequirements arm64")
    if hardware_requirements(intel_items[0]) or "sparkle:hardwareRequirements" in intel_items[0]:
        raise SystemExit("Intel 的 appcast 不应声明 hardwareRequirements")
    insertion = "\n".join(intel_items) + "\n"
    return apple_xml.replace("</channel>", insertion + "</channel>", 1)


def main() -> None:
    if len(sys.argv) == 5 and sys.argv[1] == "combine":
        apple_path, intel_path, output_path = map(Path, sys.argv[2:])
        combined = combine(
            apple_path.read_text(encoding="utf-8"),
            intel_path.read_text(encoding="utf-8"),
        )
        output_path.write_text(combined, encoding="utf-8")
        return
    if len(sys.argv) != 4:
        raise SystemExit(
            "用法: merge_appcast.py NEW.xml OLD.xml OUTPUT.xml\n"
            "或: merge_appcast.py combine APPLE.xml INTEL.xml OUTPUT.xml"
        )
    new_path, old_path, output_path = map(Path, sys.argv[1:])
    old_xml = old_path.read_text(encoding="utf-8") if old_path.is_file() else None
    merged = merge(new_path.read_text(encoding="utf-8"), old_xml)
    output_path.write_text(merged, encoding="utf-8")


if __name__ == "__main__":
    main()
