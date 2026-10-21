import importlib.util
from pathlib import Path
from unittest.mock import patch

import pytest


spec = importlib.util.spec_from_file_location(
    "upload_all", Path(__file__).resolve().parents[1] / "recipes" / "upload_all.py"
)
upload_all = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upload_all)


@pytest.mark.parametrize("channel, expected", [
    ("rock-the-conda", "rock-the-conda"),
    ("https://prefix.dev/rock-the-conda-strix/", "rock-the-conda-strix"),
    ("rock-the-conda/generic-subset", "rock-the-conda/generic-subset"),
    ("https://prefix.dev/rock-the-conda/generic-subset/", "rock-the-conda/generic-subset"),
])
def test_channel_reference(channel, expected):
    assert upload_all.channel_reference(channel) == expected


def test_upload_preserves_namespace(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(
        "ROCK_THE_CONDA_TARGET_CHANNEL",
        "https://prefix.dev/rock-the-conda/generic-subset",
    )
    monkeypatch.delenv("ROCK_THE_CONDA_PREFIX_DEV_TOKEN", raising=False)
    package = Path("output/linux-64/example-1.0-0.conda")
    package.parent.mkdir(parents=True)
    package.touch()

    with patch.object(upload_all.subprocess, "run") as run:
        run.return_value.stdout = ""
        with pytest.raises(SystemExit) as result:
            upload_all.main()

    assert result.value.code == 0
    run.assert_called_once_with(
        ["pixi", "upload", "prefix", "--verbose", "--channel",
         "rock-the-conda/generic-subset", str(package)],
        check=True, capture_output=True, text=True,
    )
