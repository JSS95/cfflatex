"""Exercise release-note extraction through the same CLI used by CD."""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        scripts = self.root / ".ci"
        scripts.mkdir()
        for name in ("check_versions.py", "release_notes.py"):
            shutil.copyfile(Path(__file__).with_name(name), scripts / name)
        self.script = scripts / "release_notes.py"
        self.changelog = self.root / "CHANGELOG.md"
        self.entry = (
            "## [1.2.3] - 2026-11-06\n\n### Added\n\n"
            "- 새 기능: `\\cff{title}`; literal $(example), `code`, and **Markdown**.\n"
        )
        self.changelog.write_text(
            "# Changelog\n\n## Unreleased\n\nFuture work.\n\n"
            + self.entry
            + "\n## [1.2.2] - 2026-11-05\n\nOlder work.\n",
            encoding="utf-8",
        )
        self.package = self.root / "cfflatex.sty"
        self.package.write_text(
            "\\ProvidesExplPackage{cfflatex}{2026-11-06}{1.2.3}\n",
            encoding="utf-8",
        )
        self.citation = self.root / "CITATION.cff"
        self.citation.write_text("cff-version: 1.2.0\n", encoding="utf-8")

    def run_notes(self, tag="v1.2.3"):
        return subprocess.run(
            [sys.executable, str(self.script), "--tag", tag],
            cwd=self.script.parent,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_only_selected_entry_is_printed_with_markdown_intact(self):
        result = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.entry)

    def test_last_entry_does_not_require_a_following_heading(self):
        self.changelog.write_text(self.entry, encoding="utf-8")
        result = self.run_notes()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.entry)

    def test_invalid_tags_fail_without_printing_notes(self):
        for tag in ("1.2.3", "v1.2", "v01.2.3", "v1.2.3/../../other"):
            with self.subTest(tag=tag):
                result = self.run_notes(tag)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Release tags", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_missing_or_undated_entry_fails_even_under_unreleased(self):
        for entry in ("Unreleased", "[1.2.3]", "[1.2.3] - pending"):
            with self.subTest(entry=entry):
                self.changelog.write_text(f"## {entry}\n\nDevelopment.\n")
                result = self.run_notes()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Expected one dated [1.2.3]", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_duplicate_entry_fails(self):
        self.changelog.write_text(self.entry + "\n" + self.entry, encoding="utf-8")
        result = self.run_notes()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected one dated [1.2.3]", result.stderr)

    def test_empty_or_headings_only_entry_fails(self):
        for body in ("", "\n### Added\n\n### Fixed\n"):
            with self.subTest(body=body):
                self.changelog.write_text("## [1.2.3] - 2026-11-06\n" + body)
                result = self.run_notes()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("has no description", result.stderr)

    def test_package_version_and_date_must_match_selected_entry(self):
        original = self.package.read_text()
        for old, new, field in (
            ("1.2.3", "1.2.4", "version"),
            ("2026-11-06", "2026-11-05", "date"),
        ):
            with self.subTest(field=field):
                self.package.write_text(original.replace(old, new))
                result = self.run_notes()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"cfflatex.sty {field} must match", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_invalid_calendar_date_fails(self):
        self.changelog.write_text(self.entry.replace("11-06", "02-30"))
        result = self.run_notes()
        self.assertNotEqual(result.returncode, 0)

    def test_citation_metadata_must_match_selected_entry(self):
        self.citation.write_text("version: 1.2.2\n")
        result = self.run_notes()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CITATION.cff version must match", result.stderr)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
