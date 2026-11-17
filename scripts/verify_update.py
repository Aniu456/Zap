#!/usr/bin/env python3
"""Verify final release archives against the pinned public key and all feeds.

Run on macOS: python3 scripts/verify_update.py <dist-directory> <version>
Only public information is needed; no private key or Keychain access.
"""
import argparse
import plistlib
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
ROOT = Path(__file__).resolve().parent.parent


def verify(directory, version):
    with (ROOT / 'Config/Sparkle-Info.plist').open('rb') as source:
        public_key = plistlib.load(source)['SUPublicEDKey']
    with tempfile.TemporaryDirectory(prefix='zap-verify-') as temporary:
        verifier = Path(temporary) / 'verify-eddsa'
        subprocess.run([
            'xcrun', 'swiftc', '-module-cache-path', str(Path(temporary) / 'cache'),
            str(ROOT / 'scripts/verify_eddsa.swift'), '-o', str(verifier),
        ], check=True)
        for slug in ('apple-silicon', 'intel'):
            archive = directory / f'Zap-{version}-{slug}.zip'
            with zipfile.ZipFile(archive) as package:
                info = plistlib.loads(package.read('Zap.app/Contents/Info.plist'))
            expected = {
                'CFBundleIdentifier': 'com.aniu456.Zap',
                'CFBundleVersion': version,
                'CFBundleShortVersionString': version,
                'SUPublicEDKey': public_key,
            }
            for key, value in expected.items():
                if info.get(key) != value:
                    raise ValueError(f'{archive.name}: invalid {key}')
            feed_name = f'appcast-{slug}.xml'
            if not info.get('SUFeedURL', '').endswith('/' + feed_name):
                raise ValueError(f'{archive.name}: incorrect update feed')
            for name in (feed_name, 'appcast.xml'):
                tree = ET.parse(directory / name)
                matches = [item for item in tree.findall('./channel/item')
                           if item.findtext(SPARKLE + 'version') == version
                           and item.find('enclosure') is not None
                           and item.find('enclosure').get('url', '').endswith('/' + archive.name)]
                if len(matches) != 1:
                    raise ValueError(f'{name}: expected one entry for {archive.name}')
                enclosure = matches[0].find('enclosure')
                if int(enclosure.get('length', '-1')) != archive.stat().st_size:
                    raise ValueError(f'{name}: archive length mismatch')
                subprocess.run([str(verifier), public_key,
                                enclosure.get(SPARKLE + 'edSignature', ''),
                                str(archive)], check=True)
            print(f'Verified {archive.name}: embedded key and both feed signatures')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    verify(args.directory, args.version)
