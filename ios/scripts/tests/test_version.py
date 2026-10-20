import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("prepare_version", pathlib.Path(__file__).resolve().parents[1] / "prepare_version.py")
versioning = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versioning)


class VersionMetadataTests(unittest.TestCase):
    def test_four_part_display_maps_to_apple_version_fields(self):
        self.assertEqual(versioning.version_fields("2026.1.2.15"), {
            "CFBundleShortVersionString": "2026.1.2", "CFBundleVersion": "15", "HFUTDisplayVersion": "2026.1.2.15",
        })

    def test_calendar_and_format_reject_invalid_versions(self):
        for value in ["2026.02.20.1", "2026.2.30.1", "2026.1.1.-1", "0.1.0", "2026.1.1.10000", "2026.1.1.01"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                versioning.version_fields(value)


if __name__ == "__main__":
    unittest.main()
