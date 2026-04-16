#!/usr/bin/env python3
"""
Deterministic auto-fixer for SKILL.md frontmatter.

Handles the three classes of errors produced by validate-skill-frontmatter.sh:

1. name-dirname-mismatch  → set `name` field to parent directory name
2. missing-description    → extract from "## WHAT" block, first paragraph
                            after the heading, or body opening paragraph
3. no-frontmatter         → prepend a new frontmatter block using directory
                            name + extracted description

Idempotent. Safe to run repeatedly. Only edits files the validator flags.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = REPO_ROOT / "scripts" / "validate-skill-frontmatter.sh"

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*(\n|$)", re.DOTALL)
NAME_FIELD_RE = re.compile(r"^(name:\s*)(.+?)(\s*)$", re.MULTILINE)
DESC_FIELD_RE = re.compile(r"^description:\s*", re.MULTILINE)


def run_validator() -> list[tuple[str, str]]:
    """Return list of (file, error_type) for each broken file."""
    env = os.environ.copy()
    r = subprocess.run(
        [str(VALIDATOR)],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        env=env,
    )
    broken: list[tuple[str, str]] = []
    current_err: str | None = None
    for line in r.stdout.splitlines():
        m = re.match(r"^\s+\[([a-z0-9-]+)\]", line)
        if m:
            current_err = m.group(1)
            continue
        m = re.match(r"^\s+(\./.+SKILL\.md)", line)
        if m and current_err:
            broken.append((m.group(1), current_err))
    return broken


def extract_description(body: str) -> str | None:
    """Extract a good description sentence from the markdown body."""
    lines = body.splitlines()

    # Strip common heading + blank prefix
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    # Skip leading H1
    if i < len(lines) and lines[i].startswith("# "):
        i += 1
    while i < len(lines) and not lines[i].strip():
        i += 1

    # Try "## WHAT" / "## Overview" sections first
    for marker in ("## WHAT", "## Overview", "## What", "## Description"):
        idx = body.find("\n" + marker)
        if idx < 0 and body.startswith(marker):
            idx = 0
        if idx >= 0:
            section = body[idx:].split("\n", 1)[1] if "\n" in body[idx:] else ""
            # Grab first non-empty non-list paragraph
            para = []
            for line in section.splitlines():
                s = line.strip()
                if not s and para:
                    break
                if s.startswith("#"):
                    if para:
                        break
                    continue
                if s.startswith(("- ", "* ", "> ")):
                    if para:
                        break
                    continue
                if s:
                    para.append(s)
            text = " ".join(para).strip()
            if 30 <= len(text) <= 900:
                return text
            if text and len(text) > 20:
                return text[:900].rstrip() + ("..." if len(text) > 900 else "")

    # Fallback: first non-heading paragraph in the body
    para: list[str] = []
    for line in lines[i:]:
        s = line.strip()
        if not s and para:
            break
        if s.startswith("#"):
            if para:
                break
            continue
        if s.startswith(("- ", "* ", "> ", "|", "```")):
            if para:
                break
            continue
        if s:
            para.append(s)
    text = " ".join(para).strip()
    if text:
        if len(text) > 900:
            text = text[:900].rstrip() + "..."
        return text
    return None


def infer_description_from_dirname(dirname: str) -> str:
    # Last-resort generic description
    pretty = dirname.replace("-", " ")
    return (
        f"Skill covering {pretty}. Use when the agent is working on "
        f"{pretty}-related tasks and needs conventions, patterns, or examples."
    )


def fix_no_frontmatter(path: Path, dirname: str) -> bool:
    content = path.read_text()
    if content.startswith("---"):
        return False
    desc = extract_description(content) or infer_description_from_dirname(dirname)
    # YAML-escape description: wrap in double quotes if it contains : or "
    if '"' in desc or ":" in desc or desc.startswith(("{", "[", "&", "*", "!", "|", ">", "'", "%", "@", "`")):
        desc_yaml = '"' + desc.replace("\\", "\\\\").replace('"', '\\"') + '"'
    else:
        desc_yaml = desc
    new = f"---\nname: {dirname}\ndescription: {desc_yaml}\n---\n\n{content}"
    path.write_text(new)
    return True


def fix_name_mismatch(path: Path, dirname: str) -> bool:
    content = path.read_text()
    m = FRONTMATTER_RE.match(content)
    if not m:
        return False
    fm = m.group(1)
    new_fm, n = NAME_FIELD_RE.subn(rf"\g<1>{dirname}\g<3>", fm, count=1)
    if n == 0 or new_fm == fm:
        return False
    content = content[: m.start(1)] + new_fm + content[m.end(1) :]
    path.write_text(content)
    return True


def fix_missing_description(path: Path, dirname: str) -> bool:
    content = path.read_text()
    m = FRONTMATTER_RE.match(content)
    if not m:
        return False
    fm = m.group(1)
    if DESC_FIELD_RE.search(fm):
        return False

    body = content[m.end() :]
    desc = extract_description(body) or infer_description_from_dirname(dirname)
    if '"' in desc or ":" in desc or desc.startswith(("{", "[", "&", "*", "!", "|", ">", "'", "%", "@", "`")):
        desc_yaml = '"' + desc.replace("\\", "\\\\").replace('"', '\\"') + '"'
    else:
        desc_yaml = desc

    # Insert description after name (or at end of frontmatter)
    if NAME_FIELD_RE.search(fm):
        new_fm = NAME_FIELD_RE.sub(
            lambda mm: f"{mm.group(1)}{mm.group(2)}{mm.group(3)}\ndescription: {desc_yaml}",
            fm,
            count=1,
        )
    else:
        new_fm = fm.rstrip() + f"\ndescription: {desc_yaml}"
    content = content[: m.start(1)] + new_fm + content[m.end(1) :]
    path.write_text(content)
    return True


def main() -> int:
    broken = run_validator()
    if not broken:
        print("✓ No broken files")
        return 0

    print(f"Found {len(broken)} file(s) with frontmatter errors.\n")

    fixed = 0
    unfixed: list[tuple[str, str, str]] = []
    for rel, err in broken:
        path = REPO_ROOT / rel.lstrip("./")
        dirname = path.parent.name
        try:
            if err == "no-frontmatter":
                ok = fix_no_frontmatter(path, dirname)
                kind = "prepended frontmatter"
            elif err == "name-dirname-mismatch":
                ok = fix_name_mismatch(path, dirname)
                kind = f"renamed to {dirname}"
            elif err == "missing-description":
                ok = fix_missing_description(path, dirname)
                kind = "added description"
            else:
                ok = False
                kind = f"unknown error type: {err}"
        except Exception as e:  # noqa: BLE001
            unfixed.append((rel, err, f"exception: {e}"))
            continue

        if ok:
            fixed += 1
            print(f"  ✓ {rel}  ({kind})")
        else:
            unfixed.append((rel, err, "no-op"))
            print(f"  ✗ {rel}  ({kind}, but no-op)")

    print(f"\nFixed {fixed}/{len(broken)} files.")
    if unfixed:
        print("\nUnfixed:")
        for rel, err, reason in unfixed:
            print(f"  - {rel} [{err}] — {reason}")

    return 0 if not unfixed else 1


if __name__ == "__main__":
    sys.exit(main())
