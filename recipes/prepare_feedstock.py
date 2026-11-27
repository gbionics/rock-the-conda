"""Check out a pinned upstream feedstock and apply its local ROCm overlay."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess


def prepare(directory: Path, repository: str, commit: str, patch: Path) -> None:
    patch = patch.resolve(strict=True)

    def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(directory), *args],
            check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    if not (directory / ".git").exists():
        directory.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", repository, str(directory)], check=True)
    head = git("rev-parse", "--verify", "HEAD", check=False).stdout.strip()
    if head != commit:
        if git("status", "--porcelain").stdout.strip():
            raise RuntimeError(f"{directory} has local changes; cannot change its pinned commit")
        git("remote", "set-url", "origin", repository)
        if git("cat-file", "-e", f"{commit}^{{commit}}", check=False).returncode:
            git("fetch", "origin", commit)
        git("checkout", "--detach", commit)
    # Repeated downloads must preserve the already-applied overlay. Other local
    # edits are left in place; a conflicting edit makes git apply fail visibly.
    if git("apply", "--reverse", "--check", str(patch), check=False).returncode == 0:
        return
    git("apply", "--check", str(patch))
    git("apply", str(patch))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("repository")
    parser.add_argument("commit")
    parser.add_argument("patch", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.directory, args.repository, args.commit, args.patch)
    except subprocess.CalledProcessError as exc:
        parser.exit(1, exc.stderr or str(exc))
    except RuntimeError as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
