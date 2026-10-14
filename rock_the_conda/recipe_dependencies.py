"""Collect dependencies without solving or building every recipe variant.

Both branches of selectors are considered conservatively. Template expressions
are replaced before YAML parsing so v0 recipes do not need to be rendered by
conda-build (which would require resolving their build environments).
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterator

import jinja2
from jinja2.sandbox import SandboxedEnvironment
import ruamel.yaml


_EXPRESSION = re.compile(r"\$?\{\{(.*?)\}\}", re.DOTALL)
_DIRECTIVE = re.compile(r"\{%.*?%\}|\{#.*?#\}", re.DOTALL)
_PACKAGE = re.compile(r"[a-z0-9][a-z0-9_.-]*", re.IGNORECASE)
_ENV = SandboxedEnvironment(undefined=jinja2.StrictUndefined)
_ENV.globals.update(
    pin_compatible=lambda name, **kwargs: name,
    pin_subpackage=lambda name, **kwargs: name,
)


def _walk_requirements(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from _walk_requirements(item)
    elif isinstance(value, dict):
        branches = (value.get("then"), value.get("else")) if "if" in value else value.values()
        for item in branches:
            yield from _walk_requirements(item)


def _requirement_groups(value: Any) -> Iterator[Any]:
    """Visit top-level, output, and test requirements, but no other strings."""
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "requirements":
                yield item
            else:
                yield from _requirement_groups(item)
    elif isinstance(value, list):
        for item in value:
            yield from _requirement_groups(item)


def _context(text: str, recipe: dict[str, Any]) -> dict[str, Any]:
    context = dict(recipe.get("context", {}))
    # Only evaluate assignments that can be resolved from local constants.
    for match in re.finditer(r"\{%\s*set\s+(\w+)\s*=\s*(.*?)%\}", text, re.DOTALL):
        try:
            context[match[1]] = _ENV.compile_expression(match[2].strip())(context)
        except (jinja2.TemplateError, TypeError, ValueError):
            continue
    return context


def _dependency_name(requirement: str, expressions: dict[str, str], context: dict[str, Any]) -> str | None:
    unresolved = False

    def substitute(match: re.Match[str]) -> str:
        nonlocal unresolved
        expression = expressions[match[0]]
        # Pin functions expose package names; compiler/stdlib helpers do not.
        if re.match(r"\s*(?:compiler|stdlib)\(", expression):
            unresolved = True
            return ""
        try:
            result = _ENV.compile_expression(expression.strip())(context)
            if result is None or result == "" or isinstance(result, jinja2.Undefined):
                unresolved = True
                return ""
            return str(result)
        except (jinja2.TemplateError, TypeError, ValueError):
            unresolved = True
            return ""

    # Only the package name matters. Unknown expressions in version/build
    # constraints are harmless; unresolved expressions in names are skipped.
    original_name = requirement.strip().split(maxsplit=1)[0] if requirement.strip() else ""
    name = re.sub(r"ROCK_TEMPLATE_\d+", substitute, original_name)
    return name.lower() if not unresolved and "ROCK_TEMPLATE_" not in name and _PACKAGE.fullmatch(name) else None


def dependencies_from_recipes(recipe_dir: str | Path) -> set[str]:
    """Read v0/v1 requirements, including outputs and conditional branches."""
    dependencies: set[str] = set()
    root = Path(recipe_dir)
    paths = sorted(set(root.glob("**/recipe.yaml")) | set(root.glob("**/meta.yaml")))
    for path in paths:
        text = path.read_text(encoding="utf-8")
        expressions: dict[str, str] = {}

        def placeholder(match: re.Match[str]) -> str:
            key = f"ROCK_TEMPLATE_{len(expressions)}"
            expressions[key] = match[1]
            return key

        sanitized = _EXPRESSION.sub(placeholder, _DIRECTIVE.sub("", text))
        yaml = ruamel.yaml.YAML(typ="safe")
        # v0 recipes commonly repeat build-string keys under line selectors.
        yaml.allow_duplicate_keys = True
        recipe = yaml.load(sanitized) or {}
        context = _context(text, recipe)
        for group in _requirement_groups(recipe):
            for requirement in _walk_requirements(group):
                name = _dependency_name(requirement, expressions, context)
                if name:
                    dependencies.add(name)
    return dependencies
