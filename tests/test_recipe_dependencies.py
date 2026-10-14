from unittest.mock import patch
import tomllib
from pathlib import Path

import pytest

from rock_the_conda.pinning import PinningError, update_pinning
from rock_the_conda.recipe_dependencies import dependencies_from_recipes


def test_v1_outputs_tests_and_both_branches(tmp_path):
    (tmp_path / "recipe.yaml").write_text('''
context:
  name: libexample
outputs:
  - package:
      name: example
    requirements:
      build:
        - ${{ compiler('c') }}
      host:
        - ${{ pin_compatible('libprotobuf') }}
        - libboost-devel >=1.88
      run:
        - if: linux
          then: liblinux
          else: libwindows
        - ${{ pin_subpackage(name, exact=True) }}
        - ${{ pin_subpackage('lib' ~ name, exact=True) }}
        - cross-python_${{ target_platform }}
        - lib${{ unknown_name }}
    tests:
      - requirements:
          run: [python, pytest]
about:
  summary: "Do not collect this string"
''')
    assert dependencies_from_recipes(tmp_path) == {
        "libprotobuf", "libboost-devel", "liblinux", "libwindows",
        "libexample", "liblibexample", "python", "pytest",
    }


def test_v0_jinja_outputs_and_multiline_assignments(tmp_path):
    (tmp_path / "meta.yaml").write_text('''
{% set headers = [
  "example",
  "other",
] %}
{% set name = "libmagma" %}
package:
  name: {{ name }}
requirements:
  build:
    - {{ compiler('cxx') }}
  host:
    - python {{ python }}.*
outputs:
  - name: magma-devel
    build:
      string: cpu  # [not win]
      string: gpu  # [win]
    requirements:
      host:
        {% if cuda_compiler_version != "None" %}
        - cuda-version {{ cuda_compiler_version }}
        {% else %}
        - rocm-core {{ hip_compiler_version }}
        {% endif %}
      run:
        - {{ pin_subpackage(name, exact=True) }}
        - {{ pin_compatible('libblas', max_pin='x') }}
''')
    assert dependencies_from_recipes(tmp_path) == {
        "python", "cuda-version", "rocm-core", "libmagma", "libblas",
    }


def test_update_reads_both_recipe_trees(tmp_path):
    for directory, filename, dependency in (
        ("recipes/local", "recipe.yaml", "fmt"),
        ("feedstocks/external-feedstock/recipe", "meta.yaml", "ffmpeg"),
    ):
        recipe_dir = tmp_path / directory
        recipe_dir.mkdir(parents=True)
        (recipe_dir / filename).write_text(f"requirements:\n  host:\n    - {dependency}\n")
    with (
        patch("rock_the_conda.pinning.download_pinning_package", return_value=(b"", {})),
        patch("rock_the_conda.pinning.select_completed_migrations", return_value=([], [])) as select,
    ):
        update_pinning(tmp_path / "pinning.yaml", latest_distribution=("new", "artifact"))
    assert select.call_args.args[1] == {"fmt", "ffmpeg"}


def test_pixi_downloads_all_feedstocks_before_update():
    manifest = tomllib.loads((Path(__file__).parents[1] / "pixi.toml").read_text())
    tasks = manifest["tasks"]
    assert tasks["rock-the-conda-pinning-update"]["depends-on"] == ["download-feedstock-all"]
    expected = {name for name in tasks if name.startswith("download-") and name.endswith("-feedstock")}
    assert set(tasks["download-feedstock-all"]["depends-on"]) == expected


def test_update_refuses_to_ignore_missing_feedstocks(tmp_path):
    recipe_dir = tmp_path / "recipes/example"
    recipe_dir.mkdir(parents=True)
    (recipe_dir / "recipe.yaml").write_text("requirements:\n  host: [python]\n")
    with (
        patch("rock_the_conda.pinning.get_latest_pinning_distribution") as download,
        pytest.raises(PinningError, match="download-feedstock-all"),
    ):
        update_pinning(tmp_path / "pinning.yaml")
    download.assert_not_called()
