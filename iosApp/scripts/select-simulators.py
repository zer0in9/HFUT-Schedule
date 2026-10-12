"""Choose iOS 26.0 devices; create them if a freshly installed runtime has none."""
import json
import subprocess

catalog = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j"]))
runtime = next((item for item in catalog["runtimes"]
                if ".iOS-" in item["identifier"] and item.get("version", "").split(".")[:2] == ["26", "0"]
                and item.get("isAvailable")), None)
if runtime is None:
    raise SystemExit("Install the iOS 26.0 simulator runtime before running tests.")
candidates = [device for device in catalog["devices"].get(runtime["identifier"], []) if device.get("isAvailable")]
for family in ("iPhone", "iPad"):
    selected = next((device for device in candidates if device["name"].startswith(family)), None)
    if selected is None:
        model_name = "iPhone 16" if family == "iPhone" else "iPad (A16)"
        model = next(item for item in catalog["devicetypes"] if item["name"] == model_name)
        udid = subprocess.check_output(["xcrun", "simctl", "create", f"HFUT {family}",
                                       model["identifier"], runtime["identifier"]], text=True).strip()
        selected = {"udid": udid}
    print(f"{family} {selected['udid']}")
