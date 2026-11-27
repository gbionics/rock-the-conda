from pathlib import Path
import subprocess

import pytest

from recipes.prepare_feedstock import prepare


def git(directory: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(directory), *args], text=True).strip()


def upstream(tmp_path):
    repository = tmp_path / "upstream"
    repository.mkdir()
    git(repository, "init")
    (repository / "recipe.yaml").write_text("build: 0\n")
    git(repository, "add", ".")
    git(repository, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Initial recipe")
    commit = git(repository, "rev-parse", "HEAD")
    (repository / "recipe.yaml").write_text("build: 1\n")
    patch = tmp_path / "rocm.patch"
    patch.write_text(git(repository, "diff") + "\n")
    git(repository, "restore", "recipe.yaml")
    return repository, commit, patch


def test_pinned_overlay_is_repeatable_and_preserves_other_edits(tmp_path):
    repository, commit, patch = upstream(tmp_path)
    checkout = tmp_path / "feedstocks" / "test"
    prepare(checkout, str(repository), commit, patch)
    (checkout / "notes.txt").write_text("local notes")
    prepare(checkout, str(repository), commit, patch)
    assert git(checkout, "rev-parse", "HEAD") == commit
    assert (checkout / "recipe.yaml").read_text() == "build: 1\n"
    assert (checkout / "notes.txt").read_text() == "local notes"


def test_conflicting_local_change_is_not_overwritten(tmp_path):
    repository, commit, patch = upstream(tmp_path)
    checkout = tmp_path / "checkout"
    prepare(checkout, str(repository), commit, patch)
    (checkout / "recipe.yaml").write_text("build: 99\n")
    with pytest.raises(subprocess.CalledProcessError):
        prepare(checkout, str(repository), commit, patch)
    assert (checkout / "recipe.yaml").read_text() == "build: 99\n"


def test_changing_pin_refuses_a_dirty_checkout(tmp_path):
    repository, commit, patch = upstream(tmp_path)
    checkout = tmp_path / "checkout"
    prepare(checkout, str(repository), commit, patch)
    (repository / "new.txt").write_text("next release")
    git(repository, "add", ".")
    git(repository, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Next release")
    next_commit = git(repository, "rev-parse", "HEAD")
    with pytest.raises(RuntimeError, match="local changes"):
        prepare(checkout, str(repository), next_commit, patch)
    assert git(checkout, "rev-parse", "HEAD") == commit
