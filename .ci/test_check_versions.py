"""Exercise the CI command in isolated repositories without TeX or dependencies."""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class VersionCheckTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / ".ci").mkdir()
        self.script = self.root / ".ci/check_versions.py"
        shutil.copyfile(Path(__file__).with_name("check_versions.py"), self.script)
        self.changelog = self.root / "CHANGELOG.md"
        self.changelog.write_text(
            "# Changelog\n\n## [1.2.3] - 2026-11-06\n\nA release.\n",
            encoding="utf-8",
        )
        self.package = self.root / "cfflatex.sty"
        self.package.write_text(
            "\\ProvidesExplPackage{cfflatex}{2026-11-06}{1.2.3}\n",
            encoding="utf-8",
        )
        self.citation = self.root / "CITATION.cff"
        self.citation.write_text(
            "cff-version: 1.2.0\npreferred-citation:\n  version: 9.9.9\n",
            encoding="utf-8",
        )

    def run_check(self):
        # Resolve the repository from the script, independently of the cwd.
        return subprocess.run(
            [sys.executable, str(self.script)],
            cwd=self.script.parent,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_matching_package_without_optional_citation_fields_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("match CHANGELOG.md: 1.2.3 (2026-11-06)", result.stdout)

    def test_package_version_and_date_mismatches_fail(self):
        original = self.package.read_text()
        for old, new, field in (
            ("1.2.3", "1.2.2", "version"),
            ("2026-11-06", "2026-11-05", "date"),
        ):
            with self.subTest(field=field):
                self.package.write_text(original.replace(old, new))
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"cfflatex.sty {field} must match", result.stderr)

    def test_missing_or_commented_package_declaration_fails(self):
        for package in ("", "% " + self.package.read_text()):
            with self.subTest(package=package):
                self.package.write_text(package)
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Missing ProvidesExplPackage", result.stderr)

    def test_multiline_package_declaration_passes(self):
        self.package.write_text(
            "\\ProvidesExplPackage\n  {cfflatex}\n  {2026-11-06}\n  {1.2.3}\n"
        )
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_development_heading_skips_without_reading_metadata_or_older_releases(self):
        released = self.changelog.read_text()
        self.package.unlink()
        self.citation.unlink()
        for heading in (
            "Unreleased",
            "[Unreleased]",
            "[1.2.3]",
            "[1.2.3] - pending",
            "[v1.2.3] - 2026-11-06",
            "[1.2] - 2026-11-06",
            "[01.2.3] - 2026-11-06",
            "[1.2.3-rc.1] - 2026-11-06",
        ):
            with self.subTest(heading=heading):
                self.changelog.write_text(
                    f"## {heading}\n\nDevelopment.\n\n" + released
                )
                result = self.run_check()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Skipping version check", result.stdout)

    def test_changelog_without_sections_skips(self):
        self.changelog.write_text("# Changelog\n\nDevelopment.\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Skipping version check", result.stdout)

    def test_only_the_latest_release_is_compared(self):
        self.changelog.write_text(
            "## [1.2.4] - 2026-11-07\n\nNew release.\n\n" + self.changelog.read_text()
        )
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 1.2.4, found 1.2.3", result.stderr)

    def test_invalid_release_date_fails(self):
        self.changelog.write_text(self.changelog.read_text().replace("11-06", "02-30"))
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Skipping", result.stdout)

    def test_matching_citation_fields_accept_quotes_and_comments(self):
        original = self.citation.read_text()
        for quote in ("", "'", '"'):
            with self.subTest(quote=quote):
                self.citation.write_text(
                    original
                    + f"version: {quote}1.2.3{quote} # release version\n"
                    + f"date-released: {quote}2026-11-06{quote}\n"
                )
                result = self.run_check()
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_citation_mismatch_or_invalid_scalar_fails(self):
        original = self.citation.read_text()
        for field, value in (
            ("version", "1.2.2"),
            ("date-released", "2026-11-05"),
            ("version", ""),
            ("version", "1.2.3#not-a-comment"),
        ):
            with self.subTest(field=field, value=value):
                self.citation.write_text(original + f"{field}: {value}\n")
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"CITATION.cff {field} must match", result.stderr)

    def test_duplicate_citation_version_fails(self):
        self.citation.write_text("version: 1.2.3\nversion: 1.2.3\n")
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected one top-level version", result.stderr)


if __name__ == "__main__":
    unittest.main()
