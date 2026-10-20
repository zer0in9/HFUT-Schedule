#!/usr/bin/env python3
"""Inspect an xtool IPA without installing or launching it."""
import argparse
import pathlib
import plistlib
import struct
import zipfile
from prepare_version import version_fields

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('ipa', type=pathlib.Path)
parser.add_argument('--version', help='Expected full YYYY.M.D.X version')
args = parser.parse_args()
path = args.ipa
with zipfile.ZipFile(path) as archive:
    info_path, = [name for name in archive.namelist() if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('/Info.plist')]
    info = plistlib.loads(archive.read(info_path))
    assert info['CFBundleIdentifier'] == 'com.hfut.schedule.ios', info
    assert info['CFBundleDisplayName'] == '聚在工大'
    fields = version_fields(info['HFUTDisplayVersion'])
    assert all(info[key] == value for key, value in fields.items()), 'Inconsistent version metadata'
    if args.version:
        assert info['HFUTDisplayVersion'] == args.version, 'IPA does not match this workflow version'
    assert info['CFBundlePackageType'] == 'APPL'
    assert float(info['MinimumOSVersion']) >= 26
    assert set(info['UIDeviceFamily']) == {1, 2}, 'Expected a universal iPhone/iPad app'
    assert not info.get('UIRequiresFullScreen', False), 'iPad window resizing must remain enabled'
    assert not info.get('UIDesignRequiresCompatibility', False)
    assert 'UIInterfaceOrientationPortraitUpsideDown' in info['UISupportedInterfaceOrientations~ipad']
    transport = info['NSAppTransportSecurity']
    assert not transport.get('NSAllowsArbitraryLoads', False)
    assert set(transport['NSExceptionDomains']) == {'jxglstu.hfut.edu.cn'}
    executable = info_path.rsplit('/', 1)[0] + '/' + info['CFBundleExecutable']
    header = archive.read(executable)[:12]
    magic, cpu, _ = struct.unpack('<III', header)
    assert magic == 0xFEEDFACF, 'Expected 64-bit Mach-O'
    assert cpu == 0x0100000C, 'Expected arm64 iOS binary'
    assert info_path.rsplit('/', 1)[0] + '/AppIcon.png' in archive.namelist()
    for license_name in ['SwiftSoup-MIT.txt', 'LICENSE']:
        assert info_path.rsplit('/', 1)[0] + '/' + license_name in archive.namelist()
print(f'Validated {path}: iOS/iPadOS 26+, arm64, version {info["HFUTDisplayVersion"]}, icon, licenses, ATS')
