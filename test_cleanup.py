#!/usr/bin/env python3
import unittest
import tempfile
import subprocess
import sys
import os
import json
from pathlib import Path
import cleanup


class TestCleanupUtility(unittest.TestCase):
    def test_version_matches_swift_app(self):
        """Ensure Python VERSION and Swift APP_VERSION stay in sync."""
        self.assertEqual(cleanup.VERSION, "1.1.0")
        swift_code = Path("CleanupApp.swift").read_text()
        self.assertIn(f'let APP_VERSION = "{cleanup.VERSION}"', swift_code)

    def test_cli_version_flag(self):
        """Verify --version and -v flags output the expected version string."""
        for flag in ("--version", "-v"):
            res = subprocess.run(
                [sys.executable, "cleanup.py", flag],
                capture_output=True,
                text=True,
                check=True,
            )
            self.assertIn(f"macOS Disk Cleanup Utility v{cleanup.VERSION}", res.stdout)

    def test_categories_schema(self):
        """Verify all expected categories exist and have required keys."""
        expected_ids = {
            "downloads_installers",
            "user_caches",
            "system_caches",
            "user_logs",
            "package_manager_caches",
            "xcode_derived_data",
            "system_tmp",
        }
        self.assertEqual(set(cleanup.CATEGORIES.keys()), expected_ids)
        for cat_id, info in cleanup.CATEGORIES.items():
            self.assertIn("name", info)
            self.assertIn("description", info)
            self.assertIn("paths", info)
            self.assertIsInstance(info["paths"], list)

    def test_get_dir_size_all_files_vs_installers_only(self):
        """Verify get_dir_size accurately filters installer extensions when requested."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            dmg_file = tmp_path / "installer.dmg"
            pkg_file = tmp_path / "setup.pkg"
            txt_file = tmp_path / "notes.txt"

            dmg_file.write_bytes(b"a" * 1000)
            pkg_file.write_bytes(b"b" * 2500)
            txt_file.write_bytes(b"c" * 500)

            all_size = cleanup.get_dir_size(tmp_path, scan_installers_only=False)
            self.assertEqual(all_size, 4000)

            installer_size = cleanup.get_dir_size(tmp_path, scan_installers_only=True)
            self.assertEqual(installer_size, 3500)

    def test_delete_category_installers_only_preserves_other_files(self):
        """Verify cleaning downloads_installers only removes installer files and preserves documents."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            dmg_file = tmp_path / "app.dmg"
            zip_file = tmp_path / "archive.zip"
            keep_file = tmp_path / "important.pdf"

            dmg_file.write_bytes(b"x" * 100)
            zip_file.write_bytes(b"y" * 200)
            keep_file.write_bytes(b"z" * 300)

            orig_paths = cleanup.CATEGORIES["downloads_installers"]["paths"]
            try:
                cleanup.CATEGORIES["downloads_installers"]["paths"] = [str(tmp_path)]
                cleanup.delete_category("downloads_installers")
            finally:
                cleanup.CATEGORIES["downloads_installers"]["paths"] = orig_paths

            self.assertFalse(dmg_file.exists())
            self.assertFalse(zip_file.exists())
            self.assertTrue(keep_file.exists())

    def test_delete_category_general_clears_directory_contents(self):
        """Verify cleaning a cache category removes all files and subdirectories inside it."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            cache_file = tmp_path / "cache.db"
            sub_dir = tmp_path / "subdir"
            sub_dir.mkdir()
            (sub_dir / "nested.tmp").write_bytes(b"123")
            cache_file.write_bytes(b"456")

            orig_paths = cleanup.CATEGORIES["user_logs"]["paths"]
            try:
                cleanup.CATEGORIES["user_logs"]["paths"] = [str(tmp_path)]
                cleanup.delete_category("user_logs")
            finally:
                cleanup.CATEGORIES["user_logs"]["paths"] = orig_paths

            self.assertTrue(tmp_path.exists())
            self.assertEqual(list(tmp_path.iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
