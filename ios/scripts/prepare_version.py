#!/usr/bin/env python3
"""Stamp the display version without violating Apple's three-component version format."""
import argparse
import datetime as dt
import pathlib
import plistlib
import re
from zoneinfo import ZoneInfo

IOS_ROOT = pathlib.Path(__file__).resolve().parents[1]


def version_fields(version):
    match = re.fullmatch(r"(\d{4})\.([1-9]\d?)\.([1-9]\d?)\.(0|[1-9]\d*)", version)
    if not match:
        raise ValueError("Version must be YYYY.M.D.X without zero-padded month/day")
    year, month, day, count = map(int, match.groups())
    dt.date(year, month, day)
    if count > 9999:
        raise ValueError("Daily build count exceeds the iOS build-number limit")
    return {
        "CFBundleShortVersionString": f"{year}.{month}.{day}",
        "CFBundleVersion": str(count),
        "HFUTDisplayVersion": version,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--version")
    source.add_argument("--local", action="store_true", help="Use today's Shanghai date with X=0")
    args = parser.parse_args()
    today = dt.datetime.now(ZoneInfo("Asia/Shanghai")).date()
    version = args.version or f"{today.year}.{today.month}.{today.day}.0"
    info_path = IOS_ROOT / "HFUTSchedule" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(version_fields(version))
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    print(f"Stamped iPhone/iPad app version {version}")


if __name__ == "__main__":
    main()
