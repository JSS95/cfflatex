"""Compare release metadata with the first section of CHANGELOG.md, without TeX."""

import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
CHANGELOG_HEADING = re.compile(r"^##[ \t]+([^\n]+)$", re.MULTILINE)
RELEASE_HEADING = re.compile(r"\[(" + SEMVER + r")\] - (\d{4}-\d{2}-\d{2})")


def check_metadata(root: Path, version: str, date: str) -> None:
    """Require package and citation metadata to match a dated release."""
    datetime.date.fromisoformat(date)
    package = (root / "cfflatex.sty").read_text(encoding="utf-8")
    declaration = re.search(
        r"^[ \t]*\\ProvidesExplPackage\s*\{cfflatex\}\s*\{([^}]+)\}\s*\{([^}]+)\}",
        package,
        flags=re.MULTILINE,
    )
    if declaration is None:
        raise ValueError("Missing ProvidesExplPackage declaration in cfflatex.sty")
    package_date, package_version = (value.strip() for value in declaration.groups())
    for field, actual, expected in (
        ("version", package_version, version),
        ("date", package_date, date),
    ):
        if actual != expected:
            raise ValueError(
                f"cfflatex.sty {field} must match CHANGELOG.md: "
                f"expected {expected}, found {actual}"
            )

    # These CFF fields are optional. Check them when explicitly declared;
    # cff-version is the CFF schema version, and nested citations are separate.
    citation = (root / "CITATION.cff").read_text(encoding="utf-8")
    for field, expected in (("version", version), ("date-released", date)):
        values = re.findall(r"^" + field + r":[ \t]*(.*)$", citation, re.MULTILINE)
        if not values:
            continue
        if len(values) != 1:
            raise ValueError(f"Expected one top-level {field} field in CITATION.cff")
        value = re.escape(expected)
        # Accept plain, single-quoted, or double-quoted scalars and comments.
        scalar = rf"""(?:{value}|"{value}"|'{value}')(?:[ \t]+#.*)?[ \t]*"""
        if not re.fullmatch(scalar, values[0]):
            raise ValueError(
                f"CITATION.cff {field} must match CHANGELOG.md: "
                f"expected {expected}, found {values[0]}"
            )


def check(root: Path) -> bool:
    """Check a dated stable release; skip development without reading metadata."""
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    heading = CHANGELOG_HEADING.search(changelog)
    entry = RELEASE_HEADING.fullmatch(heading[1].strip()) if heading else None
    if entry is None:
        print(
            "Skipping version check: the first CHANGELOG.md section "
            "is not a dated stable release."
        )
        return False

    version, date = entry.groups()
    check_metadata(root, version, date)
    print(f"Release versions and dates match CHANGELOG.md: {version} ({date})")
    return True


def main() -> int:
    try:
        check(ROOT)
    except (OSError, ValueError) as error:
        print(f"Version check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
