import shutil
import json
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET

import pytest

from rock_the_conda.dependency_graph import (
    build_graph, conda_forge_packages, graph_dot, main, published_recipes,
    recipe_supports_rocm, rocm_ready_recipes, upstream_supports_rocm,
    staged_recipe_prs,
)
from rock_the_conda.recipe_dependencies import packages_from_recipe


def write_recipe(root, directory, text, filename="recipe.yaml"):
    path = root / directory / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def test_graph_maps_all_outputs_to_recipes_and_filters_external_and_self_edges(tmp_path):
    write_recipe(tmp_path, "recipes/hipcub", '''
context:
  name: hipcub
recipe:
  name: hipcub-split
outputs:
  - staging:
      name: hipcub-build
    requirements:
      host: [rocm-core, cmake]
      build: ["${{ compiler('hip') }}"]
  - package:
      name: lib${{ name }}
    inherit: hipcub-build
  - package:
      name: lib${{ name }}-devel
    inherit:
      from: hipcub-build
      run_exports: false
    requirements:
      run: ["${{ pin_subpackage('lib' ~ name) }}"]
''')
    write_recipe(tmp_path, "recipes/rocm-core", "package:\n  name: rocm-core\n")
    write_recipe(tmp_path, "recipes/hip", "package:\n  name: hip-rocm-clang_linux-64\n")
    write_recipe(tmp_path, "recipes/isolated", "package:\n  name: isolated\n")
    write_recipe(tmp_path, "feedstocks/consumer-feedstock/recipe", '''
{% set name = "consumer-package" %}
package:
  name: {{ name }}
requirements:
  host:
    - libhipcub-devel >=1
  run:
    - {{ pin_compatible('libhipcub') }}
    - external
''', "meta.yaml")
    recipes, edges = build_graph(tmp_path)
    assert set(recipes) == {"hipcub", "rocm-core", "hip", "consumer", "isolated"}
    assert edges == {("rocm-core", "hipcub"), ("hip", "hipcub"), ("hipcub", "consumer")}
    dot = graph_dot(recipes, edges, tmp_path)
    assert '"hipcub" -> "consumer";' in dot
    assert "libhipcub" not in dot
    assert '"isolated"' in dot


def test_requirements_include_both_branches_but_not_tests_exports_or_constraints(tmp_path):
    path = write_recipe(tmp_path, "recipes/example", '''
package:
  name: example
requirements:
  host:
    - if: linux
      then: liblinux
      else: libwindows
  run_exports: [export-only]
  run_constraints: [constraint-only]
tests:
  - requirements:
      run: [test-only]
''')
    assert packages_from_recipe(path) == {"example": {"liblinux", "libwindows"}}


def test_v0_outputs_keep_common_requirements_without_synthetic_parent(tmp_path):
    path = write_recipe(tmp_path, "recipes/magma", '''
{% set name = "libmagma" %}
package:
  name: {{ name }}-split
requirements:
  build: [rocm-core]
outputs:
  - name: {{ name }}
  - name: {{ name }}-devel
    requirements:
      run:
        - {{ pin_subpackage(name, exact=True) }}
''', "meta.yaml")
    assert packages_from_recipe(path) == {
        "libmagma": {"rocm-core"}, "libmagma-devel": {"rocm-core", "libmagma"},
    }


def test_missing_configured_feedstock_is_an_error_even_if_others_exist(tmp_path):
    write_recipe(tmp_path, "feedstocks/present-feedstock/recipe", "package:\n  name: present\n")
    (tmp_path / "pixi.toml").write_text('cmd = "build ./feedstocks/missing-feedstock/recipe"')
    with pytest.raises(ValueError, match="download-feedstock-all"):
        build_graph(tmp_path)


def test_published_recipe_uses_output_names_and_colors_only_matching_recipes(tmp_path):
    path = write_recipe(tmp_path, "recipes/hipcub", '''
recipe:
  name: hipcub-split
outputs:
  - package:
      name: libhipcub-devel
''')
    other = write_recipe(tmp_path, "recipes/other", "package:\n  name: new-output\n")
    recipes = {"hipcub": path, "other": other}
    assert published_recipes(recipes, {"hipcub", "other"}) == {"hipcub", "other"}
    assert published_recipes(recipes, {"unrelated"}) == set()
    published = published_recipes(recipes, {"libhipcub-devel"})
    assert published == {"hipcub"}
    dot = graph_dot(recipes, set(), tmp_path, published)
    nodes = {line.strip().split()[0]: line for line in dot.splitlines() if "tooltip=" in line}
    assert 'fillcolor="#73c476"' in nodes['"hipcub"']
    assert 'fillcolor="#fde725"' in nodes['"other"']


def test_channeldata_download_and_invalid_snapshot(tmp_path):
    response = Mock()
    response.json.return_value = {"packages": {"libhipcub-devel": {}}}
    with patch("rock_the_conda.dependency_graph.requests.get", return_value=response):
        assert conda_forge_packages() == {"libhipcub-devel"}
    response.raise_for_status.assert_called_once()
    snapshot = tmp_path / "invalid.json"
    snapshot.write_text('{}')
    with pytest.raises(ValueError, match="Invalid conda-forge channeldata"):
        conda_forge_packages(snapshot)


@pytest.mark.parametrize("filename, requirement", [
    ("recipe.yaml", '${{ compiler("hip") }}'),
    ("meta.yaml", "{{ compiler('hip') }}"),
    ("recipe.yaml", "libhipblas-devel"),
    ("recipe.yaml", "rocm-core"),
])
def test_upstream_rocm_detection_uses_actual_requirements(tmp_path, filename, requirement):
    path = write_recipe(tmp_path, "upstream", f'''
package:
  name: example
requirements:
  build:
    - '{requirement}'
''', filename)
    assert recipe_supports_rocm(path)


def test_cpu_cuda_recipe_is_not_rocm_even_with_rocm_comments_and_tests(tmp_path):
    path = write_recipe(tmp_path, "upstream", '''
package:
  name: pytorch
requirements:
  build:
    - ${{ compiler('cuda') }}
  host: [cuda-version]
  run: [python]
# TODO support ROCm using compiler('hip') and rocm-core
tests:
  - requirements:
      run: [rocm-core]
about:
  summary: Supports CUDA and HIP upstream
''')
    assert not recipe_supports_rocm(path)


def test_rocm_detection_does_not_require_resolvable_output_names(tmp_path):
    path = write_recipe(tmp_path, "upstream", '''
outputs:
  - name: example-{{ unknown_variant }}
    requirements:
      run:
        - pytorch * rocm*
''', "meta.yaml")
    assert recipe_supports_rocm(path)


def test_published_cpu_package_is_yellow_until_upstream_recipe_supports_hip(tmp_path):
    path = write_recipe(tmp_path, "pytorch-cpu-feedstock/recipe", '''
package:
  name: pytorch
requirements:
  build: [cmake]
''')
    assert rocm_ready_recipes({"pytorch-cpu", "rocm-core"}, tmp_path) == {"rocm-core"}
    path.write_text(path.read_text() + "  host: [hip-devel]\n")
    assert rocm_ready_recipes({"pytorch-cpu", "rocm-core"}, tmp_path) == {"pytorch-cpu", "rocm-core"}


def test_upstream_download_uses_conda_forge_not_local_fork_and_falls_back_to_v0():
    missing = Mock(status_code=404)
    found = Mock(status_code=200, text="package:\n  name: pytorch\nrequirements:\n  host: [rocm-core]\n")
    with patch("rock_the_conda.dependency_graph.requests.get", side_effect=[missing, found]) as get:
        assert upstream_supports_rocm("pytorch-cpu")
    assert [call.args[0] for call in get.call_args_list] == [
        f"https://raw.githubusercontent.com/conda-forge/pytorch-cpu-feedstock/main/recipe/{filename}"
        for filename in ("recipe.yaml", "meta.yaml")
    ]
    found.raise_for_status.assert_called_once()


def test_missing_upstream_snapshot_fails_instead_of_marking_package_green(tmp_path):
    with pytest.raises(ValueError, match="Missing upstream recipe snapshot"):
        rocm_ready_recipes({"pytorch-cpu"}, tmp_path)


def test_staged_prs_match_recipe_paths_and_ignore_closed_and_dependency_mentions(tmp_path):
    path = write_recipe(tmp_path, "recipes/rocprim", "package:\n  name: librocprim-devel\n")
    snapshot = tmp_path / "prs.json"
    snapshot.write_text(json.dumps([
        {"number": 1, "state": "closed", "title": "Add rocprim", "files": ["recipes/rocprim/recipe.yaml"]},
        {"number": 2, "state": "open", "title": "Use rocprim in another recipe", "files": ["recipes/other/meta.yaml"]},
        {"number": 3, "state": "open", "title": "Add rocPRIM", "files": ["recipes/rocprim/meta.yaml"]},
        {"number": 4, "state": "open", "title": "Add rocprim", "files": ["recipes/rocprim/meta.yaml"]},
    ]))
    assert staged_recipe_prs({"rocprim": path}, snapshot) == {
        "rocprim": "https://github.com/conda-forge/staged-recipes/pull/3",
    }


def test_staged_queries_paginate_and_fetch_changed_paths(tmp_path):
    path = write_recipe(tmp_path, "recipes/rocprim", "package:\n  name: librocprim-devel\n")
    first = Mock()
    first.json.return_value = [{"number": 42, "state": "open", "title": "Add rocPRIM"}]
    first.links = {"next": {"url": "https://api.github.com/page2"}}
    second = Mock()
    second.json.return_value = []
    second.links = {}
    files = Mock()
    files.json.return_value = [{"filename": "recipes/rocprim/recipe.yaml", "status": "added"}]
    files.links = {}
    with patch("rock_the_conda.dependency_graph.requests.get", side_effect=[first, second, files]) as get:
        assert staged_recipe_prs({"rocprim": path}) == {
            "rocprim": "https://github.com/conda-forge/staged-recipes/pull/42",
        }
    assert get.call_count == 3


def test_graph_has_legend_and_correct_links_and_green_takes_precedence(tmp_path):
    recipes = {
        name: write_recipe(tmp_path, f"recipes/{name}", f"package:\n  name: {name}\n")
        for name in ("rocm-core", "rocprim", "new-package")
    }
    dot = graph_dot(recipes, set(), tmp_path, {"rocm-core"}, {
        "rocm-core": "https://github.com/conda-forge/staged-recipes/pull/1",
        "rocprim": "https://github.com/conda-forge/staged-recipes/pull/2",
    })
    nodes = {line.strip().split()[0]: line for line in dot.splitlines() if "tooltip=" in line}
    assert 'fillcolor="#73c476"' in nodes['"rocm-core"']
    assert 'URL="https://github.com/conda-forge/rocm-core-feedstock"' in nodes['"rocm-core"']
    assert 'fillcolor="#6baed6"' in nodes['"rocprim"']
    assert 'URL="https://github.com/conda-forge/staged-recipes/pull/2"' in nodes['"rocprim"']
    assert 'fillcolor="#fde725"' in nodes['"new-package"']
    assert 'URL="https://github.com/gbionics/rock-the-conda/blob/main/recipes/new-package/recipe.yaml"' in nodes['"new-package"']
    assert 'Green: conda-forge' in dot and 'Blue: open staged-recipes PR' in dot and 'Yellow:' in dot


@pytest.mark.skipif(shutil.which("dot") is None, reason="Graphviz not installed")
def test_cli_renders_valid_svg_and_saves_dot(tmp_path, capsys):
    write_recipe(tmp_path, "recipes/core", "package:\n  name: core\n")
    write_recipe(tmp_path, "recipes/consumer", "package:\n  name: consumer\nrequirements:\n  host: [core]\n")
    snapshot = tmp_path / "channeldata.json"
    snapshot.write_text(json.dumps({"packages": {"core": {}}}))
    prs = tmp_path / "prs.json"
    prs.write_text('[]')
    main(["-d", str(tmp_path), "--output", "graphs/deps.svg", "--dot", "graphs/deps.dot",
          "--conda-forge-channeldata", "channeldata.json", "--staged-recipes-prs", "prs.json"])
    svg = ET.parse(tmp_path / "graphs/deps.svg").getroot()
    titles = {element.text for element in svg.iter("{http://www.w3.org/2000/svg}title")}
    assert {"core", "consumer", "core->consumer"} <= titles
    assert '"core" -> "consumer";' in (tmp_path / "graphs/deps.dot").read_text()
    assert 'fillcolor="#73c476"' in (tmp_path / "graphs/deps.dot").read_text()
    links = {element.get("{http://www.w3.org/1999/xlink}href")
             for element in svg.iter("{http://www.w3.org/2000/svg}a")}
    assert "https://github.com/conda-forge/core-feedstock" in links
    assert "https://github.com/gbionics/rock-the-conda/blob/main/recipes/consumer/recipe.yaml" in links
    assert "2 recipes, 1 dependencies; 1 green recipes, 0 blue recipes" in capsys.readouterr().out
