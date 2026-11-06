"""Extract one dated CHANGELOG.md entry for a release tag, without TeX."""

import argparse
import re
from pathlib import Path

from check_versions import (
    CHANGELOG_HEADING,
    RELEASE_HEADING,
    ROOT,
    SEMVER,
    check_metadata,
)


def release_notes(root: Path, tag: str) -> str:
    """Require matching metadata and one nonempty entry, as in latex-cff."""
    match = re.fullmatch(r"v(" + SEMVER + r")", tag)
    if match is None:
        raise ValueError("Release tags must use stable semantic versions, e.g. v0.1.0")
    version = match[1]
    content = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    headings = list(CHANGELOG_HEADING.finditer(content))
    matches = [
        (index, entry)
        for index, heading in enumerate(headings)
        if (entry := RELEASE_HEADING.fullmatch(heading[1].strip()))
        and entry[1] == version
    ]
    if len(matches) != 1:
        raise ValueError(f"Expected one dated [{version}] section in CHANGELOG.md")
    index, entry = matches[0]
    check_metadata(root, version, entry[2])
    heading = headings[index]
    end = headings[index + 1].start() if index + 1 < len(headings) else len(content)
    body = content[heading.end() : end].strip()
    if not re.sub(r"^#+[^\n]*", "", body, flags=re.MULTILINE).strip():
        raise ValueError(f"Changelog section [{version}] has no description")
    return content[heading.start() : end].strip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    try:
        notes = release_notes(ROOT, args.tag)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(notes, end="")


if __name__ == "__main__":
    main()
