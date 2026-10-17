"""Render dependencies between this repository's conda recipes with Graphviz."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
from urllib.parse import quote

import requests

from rock_the_conda.recipe_dependencies import (
    _dependency_name, _walk_requirements, packages_from_recipe, read_recipe,
)


CHANNELDATA_URL = "https://conda.anaconda.org/conda-forge/channeldata.json"
STAGED_RECIPES_API = "https://api.github.com/repos/conda-forge/staged-recipes"
REPOSITORY_URL = "https://github.com/gbionics/rock-the-conda"
# General-purpose projects for which CPU/CUDA availability does not establish
# ROCm support. Values name the upstream conda-forge feedstock, never our forks.
ROCM_VARIANT_FEEDSTOCKS = {
    name: name for name in (
        "flash-attn", "libmagma", "librealsense", "llama.cpp", "onnxruntime",
        "pytorch-cpu", "torchcodec", "torchvision", "triton", "warp-lang",
    )
}
_ROCM_PACKAGE = re.compile(
    r"^(?:rocm-|hip(?:-|cc$)|lib(?:amdhip|hip|roc|miopen)|"
    r"roc(?:blas|fft|sparse|solver|rand|prim)|rccl$|migraphx)"
)


def conda_forge_packages(snapshot: Path | None = None) -> set[str]:
    """Read published package names across all conda-forge platforms."""
    if snapshot is None:
        response = requests.get(CHANNELDATA_URL, timeout=120)
        response.raise_for_status()
        data = response.json()
    else:
        data = json.loads(snapshot.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("packages"), dict):
        raise ValueError("Invalid conda-forge channeldata: expected a 'packages' mapping")
    return set(data["packages"])


def published_recipes(recipes: dict[str, Path], packages: set[str]) -> set[str]:
    """Match current outputs or a recipe's original package name in the channel."""
    return {recipe for recipe, path in recipes.items()
            if recipe in packages or packages.intersection(packages_from_recipe(path))}


def recipe_supports_rocm(path: Path) -> bool:
    """Look for declared ROCm/HIP build/host/run dependencies, ignoring comments.

    This is a recipe-level check, not proof of a successful published HIP build.
    The shared parser includes conditional requirements and compiler('hip').
    """
    # Upstream output names can depend on unknown variants (e.g. ONNX Runtime).
    # Inspect requirements directly without needing to resolve those names.
    recipe, expressions, context = read_recipe(path)
    for output in [recipe, *recipe.get("outputs", [])]:
        groups = output.get("requirements", {})
        for group in ("build", "host", "run"):
            for requirement in _walk_requirements(groups.get(group, [])):
                dependency = _dependency_name(requirement, expressions, context)
                if dependency and _ROCM_PACKAGE.match(dependency):
                    return True
                expression = expressions.get(requirement, "")
                if re.fullmatch(r"\s*compiler\(\s*['\"]hip['\"]\s*\)\s*", expression):
                    return True
                # Some downstream libraries select a ROCm PyTorch build
                # instead of depending directly on the HIP toolchain.
                if dependency in {"pytorch", "libtorch"} and re.search(r"\brocm[\w.*-]*", requirement):
                    return True
    return False


def upstream_supports_rocm(feedstock: str, snapshot: Path | None = None) -> bool:
    """Inspect conda-forge's main branch, or an explicitly supplied snapshot."""
    filenames = ("recipe.yaml", "meta.yaml")
    if snapshot is not None:
        for filename in filenames:
            path = snapshot / f"{feedstock}-feedstock" / "recipe" / filename
            if path.is_file():
                return recipe_supports_rocm(path)
        raise ValueError(f"Missing upstream recipe snapshot for {feedstock}-feedstock in {snapshot}")
    for filename in filenames:
        url = (f"https://raw.githubusercontent.com/conda-forge/"
               f"{feedstock}-feedstock/main/recipe/{filename}")
        response = requests.get(url, timeout=60)
        if response.status_code == 404:
            continue
        response.raise_for_status()
        with TemporaryDirectory(prefix="rock-conda-forge-") as directory:
            path = Path(directory) / filename
            path.write_text(response.text, encoding="utf-8")
            return recipe_supports_rocm(path)
    raise ValueError(f"Could not find upstream recipe for conda-forge/{feedstock}-feedstock")


def rocm_ready_recipes(published: set[str], snapshot: Path | None = None) -> set[str]:
    """Require upstream ROCm support for projects with CPU/CUDA alternatives."""
    candidates = sorted(published.intersection(ROCM_VARIANT_FEEDSTOCKS))
    with ThreadPoolExecutor(max_workers=8) as executor:
        supported = executor.map(
            lambda name: upstream_supports_rocm(ROCM_VARIANT_FEEDSTOCKS[name], snapshot),
            candidates,
        )
        return (published - set(candidates)) | {
            name for name, ready in zip(candidates, supported) if ready
        }


def _github_pages(url: str) -> list[dict]:
    result = []
    while url:
        response = requests.get(url, timeout=60)
        response.raise_for_status()
        result.extend(response.json())
        url = response.links.get("next", {}).get("url")
    return result


def staged_recipe_prs(recipes: dict[str, Path], snapshot: Path | None = None) -> dict[str, str]:
    """Match open submissions by recipe paths, not dependency mentions in PRs.

    Titles select candidate PRs to avoid fetching thousands of unrelated file
    lists. Recipe/output names, 'ROCm', and 'AMD' are candidate title keywords.
    Snapshots are lists of open PR records with an additional `files` path list.
    """
    aliases = {name: {name.lower(), *packages_from_recipe(path)} for name, path in recipes.items()}
    pulls = (json.loads(snapshot.read_text(encoding="utf-8")) if snapshot else
             _github_pages(f"{STAGED_RECIPES_API}/pulls?state=open&per_page=100"))
    if not isinstance(pulls, list):
        raise ValueError("Invalid staged-recipes snapshot: expected a list of PRs")
    result = {}
    for pull in sorted(pulls, key=lambda item: item["number"]):
        if pull.get("state") != "open":
            continue
        keywords = set().union(*aliases.values()) | {"rocm", "amd"}
        title = pull.get("title", "").lower()
        if not any(re.search(r"(?<![\w.-])" + re.escape(word) + r"(?![\w.-])", title)
                   for word in keywords):
            continue
        files = pull.get("files")
        if files is None:
            if snapshot:
                raise ValueError(f"Missing files for staged-recipes PR #{pull['number']} in snapshot")
            files = _github_pages(f"{STAGED_RECIPES_API}/pulls/{pull['number']}/files?per_page=100")
        directories = set()
        for item in files:
            if isinstance(item, dict) and item.get("status") == "removed":
                continue
            filename = item if isinstance(item, str) else item["filename"]
            parts = Path(filename).parts
            if len(parts) >= 3 and parts[0] == "recipes" and parts[-1] in {"recipe.yaml", "meta.yaml"}:
                directories.add(parts[1].lower())
        for name, names in aliases.items():
            if names & directories:
                result.setdefault(name, f"https://github.com/conda-forge/staged-recipes/pull/{pull['number']}")
    return result


def recipe_url(path: Path, base_dir: Path) -> str:
    """Link tracked recipes here, and downloaded feedstocks to their actual fork."""
    relative = path.relative_to(base_dir)
    if relative.parts[0] == "feedstocks":
        checkout = base_dir / "feedstocks" / relative.parts[1]
        # Downloaded recipes are gitignored in rock-the-conda. Their immutable
        # source URL avoids linking to a nonexistent file in this repository.
        if (checkout / ".git").exists():
            remote = subprocess.check_output(["git", "-C", str(checkout), "remote", "get-url", "origin"], text=True).strip()
            commit = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
            remote = remote.removesuffix(".git").replace("git@github.com:", "https://github.com/")
            if remote.startswith("https://github.com/"):
                return f"{remote}/blob/{commit}/{quote(path.relative_to(checkout).as_posix())}"
        return f"{REPOSITORY_URL}/blob/main/pixi.toml"
    return f"{REPOSITORY_URL}/blob/main/{quote(relative.as_posix())}"


def recipe_paths(base_dir: Path) -> list[Path]:
    """Find local and downloaded recipes, rejecting missing configured feedstocks."""
    manifest = base_dir / "pixi.toml"
    if manifest.exists():
        # Recipe paths occur directly in the build task commands. Reading those
        # paths also catches partially downloaded feedstock trees.
        configured = set(re.findall(r"\./(feedstocks/[\w.-]+/recipe)\b", manifest.read_text()))
        missing = [directory for directory in sorted(configured)
                   if not any((base_dir / directory / filename).is_file()
                              for filename in ("recipe.yaml", "meta.yaml"))]
        if missing:
            raise ValueError("Missing feedstock recipes: " + ", ".join(missing)
                             + "; run pixi run download-feedstock-all first")
    paths = []
    for directory in (base_dir / "recipes", base_dir / "feedstocks"):
        paths.extend(directory.rglob("recipe.yaml"))
        paths.extend(directory.rglob("meta.yaml"))
    if not paths:
        raise ValueError(f"No conda recipes found in {base_dir}")
    return sorted(paths)


def build_graph(base_dir: Path) -> tuple[dict[str, Path], set[tuple[str, str]]]:
    """Map output dependencies to producing recipes; edges point to consumers."""
    recipes: dict[str, Path] = {}
    owners: dict[str, set[str]] = {}
    dependencies: dict[str, set[str]] = {}
    for path in recipe_paths(base_dir):
        relative = path.relative_to(base_dir)
        # Use directory/feedstock names, rather than synthetic *-split names
        # or the individual package outputs (libhipcub-devel, etc.).
        recipe = relative.parts[1].removesuffix("-feedstock")
        if recipe in recipes:
            raise ValueError(f"Duplicate recipe name {recipe!r}: {recipes[recipe]} and {path}")
        recipes[recipe] = path
        packages = packages_from_recipe(path)
        dependencies[recipe] = set().union(*packages.values()) if packages else set()
        for package in packages:
            owners.setdefault(package, set()).add(recipe)
    edges = {
        (producer, consumer)
        for consumer, requirements in dependencies.items()
        for dependency in requirements
        for producer in owners.get(dependency, ())
        if producer != consumer
    }
    return recipes, edges


def graph_dot(recipes: dict[str, Path], edges: set[tuple[str, str]], base_dir: Path,
              published: set[str] | None = None,
              staged: dict[str, str] | None = None) -> str:
    """Use migration-style ellipses and a top-to-bottom dependency layout."""
    lines = [
        "digraph dependencies {",
        '  graph [rankdir=TB, labelloc=t, label=<',
        '    <TABLE BORDER="0" CELLBORDER="0" CELLSPACING="6" CELLPADDING="5">',
        '      <TR><TD COLSPAN="3">Conda recipe dependencies (dependency → dependent)</TD></TR>',
        '      <TR><TD BGCOLOR="#73c476">Green: conda-forge</TD><TD BGCOLOR="#6baed6">Blue: open staged-recipes PR</TD><TD BGCOLOR="#fde725">Yellow: no qualifying feedstock or open PR</TD></TR>',
        '      <TR><TD COLSPAN="3">Green requires upstream ROCm/HIP support for general-purpose GPU packages.</TD></TR>',
        '    </TABLE>>];',
        '  node [shape=ellipse, style=filled, fillcolor="#fde725", color=black];',
    ]
    for recipe, path in sorted(recipes.items()):
        tooltip = str(path.relative_to(base_dir).as_posix())
        available = recipe in (published or set())
        if recipe in ROCM_VARIANT_FEEDSTOCKS:
            tooltip += " — " + ("On conda-forge; upstream recipe declares ROCm/HIP dependencies"
                                  if available else "No conda-forge package with confirmed upstream ROCm/HIP recipe support")
        else:
            tooltip += " — " + ("Recipe/output name found on conda-forge"
                                  if available else "No matching package found on conda-forge")
        if available:
            color = "#73c476"
            feedstock = ROCM_VARIANT_FEEDSTOCKS.get(recipe, recipe)
            url = f"https://github.com/conda-forge/{feedstock}-feedstock"
        elif recipe in (staged or {}):
            color = "#6baed6"
            url = staged[recipe]
            tooltip = f"{path.relative_to(base_dir).as_posix()} — Open staged-recipes PR: {url}"
        else:
            color = "#fde725"
            url = recipe_url(path, base_dir)
        lines.append(f"  {json.dumps(recipe)} [tooltip={json.dumps(tooltip)}, "
                     f"fillcolor={json.dumps(color)}, URL={json.dumps(url)}, target=\"_blank\"];")
    for dependency, dependent in sorted(edges):
        lines.append(f"  {json.dumps(dependency)} -> {json.dumps(dependent)};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-d", "--directory", type=Path, default=Path("."), help="Repository root")
    parser.add_argument("--output", type=Path, default=Path("recipe_dependencies.svg"),
                        help="SVG output, relative to the repository root")
    parser.add_argument("--dot", type=Path, help="Also save the Graphviz DOT source")
    parser.add_argument("--conda-forge-channeldata", type=Path,
                        help="Use a saved conda-forge channeldata.json instead of downloading it")
    parser.add_argument("--conda-forge-recipes", type=Path,
                        help="Read saved upstream recipes from PATH/<name>-feedstock/recipe/ instead of GitHub")
    parser.add_argument("--staged-recipes-prs", type=Path,
                        help="Use saved open PR records with 'files' lists instead of querying GitHub")
    args = parser.parse_args(argv)
    base_dir = args.directory.resolve()
    try:
        recipes, edges = build_graph(base_dir)
        snapshot = base_dir / args.conda_forge_channeldata if args.conda_forge_channeldata else None
        published = published_recipes(recipes, conda_forge_packages(snapshot))
        upstream_snapshot = base_dir / args.conda_forge_recipes if args.conda_forge_recipes else None
        ready = rocm_ready_recipes(published, upstream_snapshot)
        staged_snapshot = base_dir / args.staged_recipes_prs if args.staged_recipes_prs else None
        staged = staged_recipe_prs(recipes, staged_snapshot)
        source = graph_dot(recipes, edges, base_dir, ready, staged)
        output = base_dir / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        if args.dot:
            dot_path = base_dir / args.dot
            dot_path.parent.mkdir(parents=True, exist_ok=True)
            dot_path.write_text(source, encoding="utf-8")
        subprocess.run(["dot", "-Tsvg", "-o", str(output)], input=source,
                       text=True, capture_output=True, check=True)
    except FileNotFoundError as error:
        parser.exit(1, f"{error}\nGraphviz 'dot' must be on PATH; use pixi run recipe-dependency-graph.\n")
    except subprocess.CalledProcessError as error:
        parser.exit(1, f"Graphviz failed: {error.stderr}\n")
    except requests.RequestException as error:
        parser.exit(1, f"Could not check conda-forge packages, upstream recipes, or staged-recipes PRs: {error}\n")
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    print(f"Wrote {output} ({len(recipes)} recipes, {len(edges)} dependencies; "
          f"{len(ready)} green recipes, {len(set(staged) - ready)} blue recipes)")


if __name__ == "__main__":
    main()
