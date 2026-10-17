"""Generate an AltStore Classic source from the IPA being published."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
from urllib.parse import quote
import zipfile


def generate(ipa_path, repository, tag, commit):
    with zipfile.ZipFile(ipa_path) as ipa:
        infos = [name for name in ipa.namelist()
                 if name.startswith("Payload/") and name.count("/") == 2
                 and name.endswith(".app/Info.plist")]
        if len(infos) != 1:
            raise ValueError("Expected exactly one app in Payload")
        info = plistlib.loads(ipa.read(infos[0]))
        # Include privacy declarations from the app and any embedded extensions.
        privacy = {}
        for name in ipa.namelist():
            if name.startswith("Payload/") and name.endswith("/Info.plist"):
                plist = plistlib.loads(ipa.read(name))
                privacy.update({key: value for key, value in plist.items()
                                if key.startswith("NS") and "UsageDescription" in key})

    base = f"https://github.com/{repository}"
    icon = f"https://raw.githubusercontent.com/{repository}/{commit}/src/img/logotransplant.png"
    return {
        "name": "聚在工大 · iOS",
        "identifier": f"{repository.replace('/', '.')}.altstore",
        "sourceURL": f"{base}/releases/download/altstore/source.json",
        "website": base,
        "apps": [{
            "name": "聚在工大",
            "bundleIdentifier": info["CFBundleIdentifier"],
            "developerName": "Chiu-xaH / zer0in9 与贡献者",
            "localizedDescription": "合肥工业大学课表工具 iOS 适配预览版。支持离线课程管理、周次查看、学期设置和校园网站入口。需要自行签名安装。",
            "iconURL": icon,
            "versions": [{
                "version": info["CFBundleShortVersionString"],
                "buildVersion": str(info["CFBundleVersion"]),
                "date": datetime.now(timezone.utc).isoformat(),
                "downloadURL": f"{base}/releases/download/{quote(tag, safe='')}/{quote(ipa_path.name, safe='')}",
                "size": ipa_path.stat().st_size,
                "minOSVersion": info["MinimumOSVersion"],
            }],
            # The release workflow packages an unsigned app without entitlements.
            "appPermissions": {"entitlements": [], "privacy": privacy},
        }],
        "news": [],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    source = generate(args.ipa, args.repository, args.tag, args.commit)
    args.output.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
