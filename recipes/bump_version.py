#!/usr/bin/env python3

import argparse
import hashlib
import re
import sys
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional

CHUNK_SIZE = 1 << 15
TARGET_PATTERNS = ("rocm-{{ version }}", "rocm-${{ version }}")


def compute_sha256(url: str) -> str:
    hasher = hashlib.sha256()
    print(f"Downloading {url}", flush=True)
    with urllib.request.urlopen(url) as response:
        while True:
            chunk = response.read(CHUNK_SIZE)
            if not chunk:
                break
            hasher.update(chunk)
    digest = hasher.hexdigest()
    print(f"Computed sha256 {digest} for {url}", flush=True)
    return digest


def normalize_url(raw: str) -> str:
    raw = raw.strip()
    if raw and raw[0] in ('"', "'") and raw[-1] == raw[0]:
        raw = raw[1:-1]
    return raw


def extract_url(line: str) -> Optional[str]:
    if "url:" not in line:
        return None
    _, value = line.split("url:", 1)
    return normalize_url(value)


def update_meta_version(lines: List[str], new_version: str) -> bool:
    pattern = re.compile(r'(\s*{%\s*set\s+version\s*=\s*")(.*?)("\s*%}\s*)')
    for idx, line in enumerate(lines):
        match = pattern.match(line)
        if match:
            lines[idx] = f"{match.group(1)}{new_version}{match.group(3)}\n"
            return True
    return False


def update_recipe_version(lines: List[str], new_version: str) -> bool:
    in_context = False
    updated = False
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("context:"):
            in_context = True
            continue
        if in_context and not stripped:
            in_context = False
            continue
        if in_context and stripped.startswith("version:"):
            match = re.search(r'(version:\s*)(["\'])([^"\']+)(["\'])', line)
            if match:
                start = match.start(3)
                end = match.end(3)
                lines[idx] = f"{line[:start]}{new_version}{line[end:]}"
                updated = True
                in_context = False
    return updated


def update_hashes(lines: List[str], new_version: str, cache: Dict[str, str]) -> bool:
    changed = False
    for idx, line in enumerate(lines):
        url_value = extract_url(line)
        if not url_value:
            continue
        if not any(pattern in url_value for pattern in TARGET_PATTERNS):
            continue
        rewritten_url = url_value.replace("${{ version }}", new_version).replace("{{ version }}", new_version)
        if rewritten_url not in cache:
            cache[rewritten_url] = compute_sha256(rewritten_url)
        sha_idx = None
        for look_ahead in range(1, 6):
            pos = idx + look_ahead
            if pos >= len(lines):
                break
            if "sha256:" in lines[pos]:
                sha_idx = pos
                break
        if sha_idx is None:
            continue
        sha_line = lines[sha_idx]
        match = re.search(r'(sha256:\s*)([0-9a-fA-F]+)', sha_line)
        if not match:
            continue
        lines[sha_idx] = f"{sha_line[:match.start(2)]}{cache[rewritten_url]}{sha_line[match.end(2):]}"
        changed = True
    return changed


def get_meta_version(lines: List[str]) -> Optional[str]:
    pattern = re.compile(r'(\s*{%\s*set\s+version\s*=\s*")(.*?)("\s*%}\s*)')
    for line in lines:
        match = pattern.match(line)
        if match:
            return match.group(2)
    return None


def get_recipe_version(lines: List[str]) -> Optional[str]:
    in_context = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("context:"):
            in_context = True
            continue
        if in_context and not stripped:
            in_context = False
            continue
        if in_context and stripped.startswith("version:"):
            match = re.search(r'(version:\s*)(["\'])([^"\']+)(["\'])', line)
            if match:
                return match.group(3)
    return None


def file_has_target_urls(lines: List[str]) -> bool:
    for line in lines:
        url = extract_url(line)
        if url and any(p in url for p in TARGET_PATTERNS):
            return True
    return False


def process_file(path: Path, new_version: str, cache: Dict[str, str]) -> bool:
    with path.open("r", encoding="utf-8") as handle:
        lines = handle.readlines()
    modified = False
    if path.name == "meta.yaml":
        modified |= update_meta_version(lines, new_version)
    elif path.name == "recipe.yaml":
        modified |= update_recipe_version(lines, new_version)
    modified |= update_hashes(lines, new_version, cache)
    if modified:
        with path.open("w", encoding="utf-8") as handle:
            handle.writelines(lines)
    return modified


def main() -> None:
    parser = argparse.ArgumentParser(description="Bump ROCm recipe versions and hashes")
    parser.add_argument("version", help="Target ROCm version, e.g. 7.0.2")
    args = parser.parse_args()

    recipes_root = Path(__file__).resolve().parent
    cache: Dict[str, str] = {}
    updated_files: List[Path] = []

    for entry in sorted(recipes_root.iterdir()):
        if not entry.is_dir():
            continue
        # If the recipe already declares the target version, skip downloading/updating
        meta = entry / "meta.yaml"
        recipe = entry / "recipe.yaml"

        # Read any existing files so we can inspect declared version and URLs
        meta_lines: Optional[List[str]] = None
        recipe_lines: Optional[List[str]] = None
        if meta.exists():
            with meta.open("r", encoding="utf-8") as fh:
                meta_lines = fh.readlines()
        if recipe.exists():
            with recipe.open("r", encoding="utf-8") as fh:
                recipe_lines = fh.readlines()

        declared_version = None
        if meta_lines is not None:
            declared_version = get_meta_version(meta_lines)
        elif recipe_lines is not None:
            declared_version = get_recipe_version(recipe_lines)

        rel_entry = entry.relative_to(recipes_root)
        if declared_version == args.version:
            print(f"Skipping {rel_entry}: already at version {args.version}", flush=True)
            continue

        # If neither file contains a ROCm-patterned URL, skip the whole recipe
        has_targets = False
        if meta_lines is not None and file_has_target_urls(meta_lines):
            has_targets = True
        if recipe_lines is not None and file_has_target_urls(recipe_lines):
            has_targets = True
        if not has_targets:
            print(f"Skipping {rel_entry}: no ROCm-patterned URLs found", flush=True)
            continue

        for candidate, lines in ((meta, meta_lines), (recipe, recipe_lines)):
            if candidate.exists():
                rel_path = candidate.relative_to(recipes_root)
                print(f"Processing {rel_path}", flush=True)
                if process_file(candidate, args.version, cache):
                    print(f"Updated {rel_path}", flush=True)
                    updated_files.append(candidate)

    if updated_files:
        for path in updated_files:
            rel = path.relative_to(recipes_root)
            print(f"Updated {rel}")
    else:
        print("No recipes required updates.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
