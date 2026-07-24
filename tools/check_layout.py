#!/usr/bin/env python3
"""Fail the build when a file lives somewhere the project layout forbids.

Runs first in CI (before the multi-minute Godot exports) so a misplaced file is
rejected in seconds. All rules are the data tables near the top of this file —
adding a category is a one- or two-line edit, never a code change.

  ERROR  -> blocking. Wrong location, bad name, junk file, orphaned sidecar,
            or an extension no rule covers (so the ruleset can't silently rot).
  WARN   -> loud but non-blocking. An asset that no scene or script references.

Reads `git ls-files`, so it judges exactly what is committed and ignores local
scratch files.

Usage:  python3 tools/check_layout.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import PurePosixPath

# --- RULES -------------------------------------------------------------------

# Exactly what may sit at the repository root. Anything else at root is an error
# — this is the rule that actually stops the tree from ballooning.
ROOT_FILES = {
    "project.godot", "export_presets.cfg", "icon.svg", "icon.svg.import",
    "README.md", "LICENSE", "CONTRIBUTING.md",
    ".editorconfig", ".gitattributes", ".gitignore",
}
ROOT_DIRS = {"assets", "src", "addons", "raw", "tools", "docs", ".github"}

# extension -> directory prefixes it is allowed to live under.
# A file whose extension is listed but whose path matches none of the prefixes
# is in the wrong place. An extension not listed here at all is an error.
EXT_RULES: dict[str, tuple[str, ...]] = {
    # code & scenes: feature-grouped under src/ (plus tooling and plugins)
    ".gd": ("src/", "tools/", "addons/"),
    ".tscn": ("src/", "addons/"),
    ".gdshader": ("assets/shaders/", "addons/"),
    ".tres": ("assets/", "src/", "addons/"),
    ".theme": ("assets/themes/", "addons/"),
    # media: type-grouped under assets/
    ".png": ("assets/", "addons/"),
    ".jpg": ("assets/", "addons/"),
    ".jpeg": ("assets/", "addons/"),
    ".svg": ("assets/", "addons/"),
    ".webp": ("assets/", "addons/"),
    ".mp3": ("assets/audio/",),
    ".ogg": ("assets/audio/",),
    ".wav": ("assets/audio/",),
    ".glb": ("assets/models/",),
    ".gltf": ("assets/models/",),
    ".obj": ("assets/models/",),
    ".fbx": ("assets/models/",),
    ".ttf": ("assets/fonts/",),
    ".otf": ("assets/fonts/",),
    ".woff": ("assets/fonts/",),
    ".woff2": ("assets/fonts/",),
    # editable source art Godot must NOT import -> raw/ (gdignored)
    ".aseprite": ("raw/",),
    ".ase": ("raw/",),
    ".blend": ("raw/",),
    ".psd": ("raw/",),
    ".kra": ("raw/",),
    ".xcf": ("raw/",),
    ".avif": ("raw/",),
    # docs & config
    ".md": ("",),           # allowed anywhere
    ".cfg": ("", "addons/"),
    ".godot": ("",),        # project.godot at root only (also in ROOT_FILES)
    ".py": ("tools/",),
    ".yml": (".github/",),
    ".yaml": (".github/",),
}

# Sidecars: name is parent + suffix; validated by "parent must exist", not by
# extension rules (they inherit the parent's location and name).
SIDECAR_SUFFIXES = (".import", ".uid")

# Never belong in version control.
JUNK_SUFFIXES = (".tmp", ".bak", ".orig", ".DS_Store", "~")

# Bare filenames that are allowed to break the snake_case / extension rules.
NAME_EXEMPT = {".gitkeep", ".gdignore", ".gitignore", ".gitattributes", ".editorconfig"}

# Roots whose file and directory names must be snake_case.
SNAKE_ROOTS = ("assets/", "src/", "raw/", "tools/")

# Assets we expect something to reference; unreferenced ones get a WARN.
ASSET_ROOTS = ("assets/sprites/", "assets/audio/", "assets/models/", "assets/fonts/")

# --- helpers -----------------------------------------------------------------


def git_files() -> list[str]:
    out = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, check=True
    ).stdout
    return [line for line in out.splitlines() if line]


def is_snake(segment: str) -> bool:
    """True if a path segment (file stem or dir) is lower snake_case."""
    stem = segment.split(".", 1)[0] if "." in segment else segment
    if not stem:
        return True  # dotfile like .gitkeep -> judged elsewhere
    return all(c.islower() or c.isdigit() or c == "_" for c in stem)


def full_extension(name: str) -> str:
    """Extension used for rule lookup, ignoring a trailing sidecar suffix."""
    p = PurePosixPath(name)
    if p.suffix in SIDECAR_SUFFIXES:
        p = PurePosixPath(p.stem)
    return p.suffix.lower()


def referenced_tokens(files: list[str]) -> str:
    """Concatenated text of every file that can *consume* an asset.

    Deliberately excludes .import/.uid sidecars: each asset's own sidecar
    repeats its path and uid, which would make every asset look referenced.
    """
    blob = []
    for f in files:
        if f.endswith((".tscn", ".gd", ".tres", ".godot")):
            try:
                blob.append(open(f, encoding="utf-8", errors="ignore").read())
            except OSError:
                pass
    return "\n".join(blob)


def asset_uid(path: str) -> str | None:
    """The uid a sprite/audio asset advertises via its .import sidecar."""
    imp = path + ".import"
    try:
        for line in open(imp, encoding="utf-8", errors="ignore"):
            if line.startswith("uid="):
                return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        return None
    return None


# --- checks ------------------------------------------------------------------


def main() -> int:
    files = git_files()
    fileset = set(files)
    errors: list[str] = []
    warnings: list[str] = []

    # 1) root allowlist
    for f in files:
        top = f.split("/", 1)[0]
        if "/" not in f:
            if f not in ROOT_FILES:
                errors.append(f"{f}: not an allowed root file "
                              f"(move it into a subdirectory or add it to ROOT_FILES)")
        elif top not in ROOT_DIRS:
            errors.append(f"{f}: '{top}/' is not an allowed top-level directory")

    for f in files:
        name = PurePosixPath(f).name

        # 2) hygiene: junk never gets committed
        if name.endswith(JUNK_SUFFIXES) or name == ".DS_Store":
            errors.append(f"{f}: junk/temp file must not be committed")
            continue

        # 3) sidecars: must sit beside their parent
        if name.endswith(SIDECAR_SUFFIXES):
            parent = f.rsplit(".", 1)[0]
            if parent not in fileset:
                errors.append(f"{f}: orphaned sidecar — parent '{parent}' is missing")
            continue

        # 4) naming: snake_case + no spaces under managed roots
        if " " in f:
            errors.append(f"{f}: paths must not contain spaces")
        if f.startswith(SNAKE_ROOTS) and name not in NAME_EXEMPT:
            bad = [seg for seg in f.split("/") if seg and not is_snake(seg)]
            if bad:
                errors.append(f"{f}: not snake_case -> {', '.join(bad)}")

        # 5) extension -> allowed location (skip dotfiles/keeps and root files)
        if name in NAME_EXEMPT or ("/" not in f and f in ROOT_FILES):
            continue
        ext = full_extension(name)
        if ext == "":
            continue
        if ext not in EXT_RULES:
            errors.append(f"{f}: extension '{ext}' has no rule "
                          f"(add one to EXT_RULES or move the file)")
            continue
        allowed = EXT_RULES[ext]
        if not any(f.startswith(prefix) for prefix in allowed):
            where = " or ".join(p or "<root>" for p in allowed)
            errors.append(f"{f}: '{ext}' files belong under {where}")

    # 6) unreferenced assets -> loud WARNING (non-blocking)
    blob = referenced_tokens(files)
    for f in files:
        if not f.startswith(ASSET_ROOTS):
            continue
        name = PurePosixPath(f).name
        if name in NAME_EXEMPT or name.endswith(SIDECAR_SUFFIXES):
            continue
        uid = asset_uid(f)
        if f"res://{f}" in blob or (uid and uid in blob):
            continue
        warnings.append(f"{f}: not referenced by any scene or script "
                        f"(dead asset, or content not wired up yet?)")

    # --- report --------------------------------------------------------------
    if warnings:
        print("=" * 70)
        print(f"  ⚠  {len(warnings)} UNREFERENCED ASSET(S) — not blocking, but clean me up:")
        print("=" * 70)
        for w in warnings:
            print(f"  WARN  {w}")
        print()

    if errors:
        print("=" * 70)
        print(f"  ✗  {len(errors)} LAYOUT ERROR(S) — the pipeline is blocked:")
        print("=" * 70)
        for e in errors:
            print(f"  ERROR {e}")
        print()
        print("Layout rules live in tools/check_layout.py and docs/STRUCTURE.md.")
        return 1

    print(f"✓ Layout OK — {len(files)} files, {len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
