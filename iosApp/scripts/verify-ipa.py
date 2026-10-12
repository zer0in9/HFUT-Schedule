"""Check package structure and deployment contract, independent of Xcode."""
import plistlib
import sys
import zipfile


def verify(path):
    with zipfile.ZipFile(path) as ipa:
        assert ipa.testzip() is None, "Corrupt ZIP member"
        infos = [n for n in ipa.namelist() if n.startswith("Payload/")
                 and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        assert len(infos) == 1, "Expected one app in Payload"
        info = plistlib.loads(ipa.read(infos[0]))
        assert info["CFBundleIdentifier"] == "com.hfut.schedule.ios"
        assert info["CFBundlePackageType"] == "APPL"
        assert info["MinimumOSVersion"] == "26.0"
        assert set(info["UIDeviceFamily"]) == {1, 2}, "Must support iPhone and iPad"
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Simulator payload"
        executable = infos[0].removesuffix("Info.plist") + info["CFBundleExecutable"]
        assert ipa.getinfo(executable).file_size > 0, "Missing app executable"
        assert not info.get("UIRequiresFullScreen", False), "iPad windowing must be enabled"
        orientations = set(info["UISupportedInterfaceOrientations~ipad"])
        assert len(orientations) == 4, "iPad must support all orientations"
    print(f"Verified {path}: iOS 26+, iPhone + iPad, device payload")


if __name__ == "__main__":
    verify(sys.argv[1])
