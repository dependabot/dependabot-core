"""Edit dependency declarations in a Poetry ``pyproject.toml``.

Uses tomlkit, which Poetry itself uses to read and write ``pyproject.toml``,
so only the edited value changes. Comments, quoting, spacing and the rest
of the file stay byte-for-byte the same.

Ruby passes the requirement it parsed and the requirement it wants. This
module finds the declaration that currently has the old requirement and
rewrites it. It doesn't decide what the new requirement should be.
"""

import json
import re

import tomlkit
from packaging.requirements import InvalidRequirement, Requirement
from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.utils import canonicalize_name
from tomlkit.items import AoT, Array, String, StringType, Table, InlineTable

MAIN_GROUP = "dependencies"
LEGACY_DEV_GROUP = "dev-dependencies"
BUILD_SYSTEM_GROUP = "build-system.requires"

# Returned by a replace function that edited a table in place.
IN_PLACE = object()

SPECIFIER_RE = re.compile(r"([!<>=~]+)\s*([^\s,;]+)")


def update_poetry_declarations(content, edits):
    """Apply each edit to ``content`` in order.

    Each edit is a dict with ``name``, ``group`` (the Ruby requirement group:
    ``dependencies``, ``dev-dependencies``, or a group/extra name; None
    searches every table) and either
    ``old_requirement``/``new_requirement`` or ``old_tag``/``new_tag`` for a
    git dependency. ``extras`` (a list) narrows PEP 508 matches.

    Returns the new content plus one boolean per edit saying whether it found
    a declaration to change. Ruby keeps its regex fallback for the rest.
    """
    try:
        document = tomlkit.parse(content)
        applied = [_apply(document, edit) for edit in edits]
        result = {"content": tomlkit.dumps(document), "applied": applied}
    except Exception as e:
        print(json.dumps({"error": repr(e), "error_class": type(e).__name__}))
        exit(1)

    return json.dumps({"result": result})


def _apply(document, edit):
    name = canonicalize_name(edit["name"])
    group = edit["group"]

    if edit.get("old_tag") is not None:
        return _apply_to_poetry_tables(
            document, group, name,
            lambda value: _replace_git_tag(
                value, edit["old_tag"], edit["new_tag"]
            ),
        )

    old = edit["old_requirement"]
    new = edit["new_requirement"]

    # Poetry's own tables come first, matching the regex updater's order.
    if _apply_to_poetry_tables(
        document, group, name,
        lambda value: _replace_poetry_constraint(value, old, new),
    ):
        return True

    # Ruby merges declarations of one package with different extras into a
    # single dependency with one ``extras`` value, so retry ignoring extras.
    extras = set(edit.get("extras") or [])
    for wanted_extras in (extras, None):
        for array in _pep508_arrays(document, group):
            if _replace_pep508(array, name, wanted_extras, old, new):
                return True
    return False


# --- [tool.poetry] tables ---------------------------------------------------


def _poetry_tables(document, group):
    poetry = _get(document, "tool", "poetry")
    if poetry is None:
        return []
    if group is None:
        groups = [MAIN_GROUP, LEGACY_DEV_GROUP, *(poetry.get("group") or {})]
        return [t for g in groups for t in _poetry_tables(document, g)]
    if group in (MAIN_GROUP, LEGACY_DEV_GROUP):
        table = poetry.get(group)
        return [table] if table is not None else []

    groups = poetry.get("group") or {}
    return [
        value.get("dependencies")
        for key, value in groups.items()
        if _same_group(key, group) and value.get("dependencies") is not None
    ]


def _apply_to_poetry_tables(document, group, name, replace):
    for table in _poetry_tables(document, group):
        for key in list(table.keys()):
            if canonicalize_name(key) != name:
                continue
            if _replace_in(table, key, replace):
                return True
            # A declaration may be a list of per-marker constraints (#5862).
            if isinstance(table[key], (Array, AoT)):
                entries = table[key]
                if any(
                    _replace_in(entries, i, replace)
                    for i in range(len(entries))
                ):
                    return True
    return False


def _replace_in(container, key, replace):
    """Run ``replace`` on ``container[key]``.

    ``replace`` returns None for no match, IN_PLACE when it edited a table
    itself, or a new value to store.
    """
    replaced = replace(container[key])
    if replaced is None:
        return False
    if replaced is not IN_PLACE:
        container[key] = replaced
    return True


def _replace_poetry_constraint(value, old, new):
    """Return the replacement for ``value``, or None if it doesn't match."""
    if isinstance(value, str):
        return _string_like(value, new) if _same(value, old) else None
    if isinstance(value, (Table, InlineTable)):
        version = value.get("version")
        if isinstance(version, str) and _same(version, old):
            value["version"] = _string_like(version, new)
            return IN_PLACE
    return None


def _replace_git_tag(value, old_tag, new_tag):
    if not isinstance(value, (Table, InlineTable)) or "git" not in value:
        return None
    tag = value.get("tag")
    if isinstance(tag, str) and str(tag) == old_tag:
        value["tag"] = _string_like(tag, new_tag)
        return IN_PLACE
    return None


def _same(current, wanted):
    return re.sub(r"\s+", "", str(current)) == re.sub(r"\s+", "", wanted)


# --- PEP 508 arrays ---------------------------------------------------------


def _pep508_arrays(document, group):
    """PEP 621, PEP 735 and build-system arrays a Ruby group can refer to.

    Ruby labels ``[project.dependencies]`` as ``dependencies`` and both
    optional-dependency extras and PEP 735 groups by their own name, so a
    label can match several tables.
    """
    arrays = []
    project = document.get("project") or {}
    if group is None:
        groups = [
            MAIN_GROUP, BUILD_SYSTEM_GROUP,
            *(project.get("optional-dependencies") or {}),
            *(document.get("dependency-groups") or {}),
        ]
        return [a for g in groups for a in _pep508_arrays(document, g)]
    if group == MAIN_GROUP:
        arrays.append(project.get("dependencies"))
    elif group == BUILD_SYSTEM_GROUP:
        arrays.append(_get(document, "build-system", "requires"))
    else:
        for tables in (
            project.get("optional-dependencies") or {},
            document.get("dependency-groups") or {},
        ):
            arrays.extend(
                value for key, value in tables.items()
                if _same_group(key, group)
            )
    return [a for a in arrays if isinstance(a, Array)]


def _replace_pep508(array, name, extras, old, new):
    try:
        old_set = SpecifierSet(old)
    except InvalidSpecifier:
        return False

    for index, entry in enumerate(array):
        # PEP 735 `{include-group = "..."}` entries aren't requirements.
        if not isinstance(entry, str):
            continue
        try:
            requirement = Requirement(str(entry))
        except InvalidRequirement:
            continue
        if canonicalize_name(requirement.name) != name:
            continue
        if requirement.url:
            continue
        if extras is not None and set(requirement.extras) != extras:
            continue
        if requirement.specifier != old_set:
            continue

        array[index] = _string_like(
            entry, _rewrite_pep508(str(entry), old, new)
        )
        return True
    return False


def _rewrite_pep508(entry, old, new):
    """Swap the specifier in ``entry`` while keeping its spacing and order.

    Each version is replaced in place, operator by operator, the way the Ruby
    ``Pep621Updater`` does it. If that can't produce the new specifier set
    (for example an operator was added or dropped), the whole specifier is
    replaced with ``new``.
    """
    start, end = _specifier_span(entry)
    original = entry[start:end]
    rewritten = _rewrite_specifiers(original, old, new)
    try:
        if SpecifierSet(rewritten) != SpecifierSet(new):
            rewritten = new
    except InvalidSpecifier:
        rewritten = new

    # Keep the space before a marker, if there was one.
    trailing = original[len(original.rstrip()):]
    return entry[:start] + rewritten.strip() + trailing + entry[end:]


def _specifier_span(entry):
    marker = entry.find(";")
    end = marker if marker != -1 else len(entry)
    close = entry.find("]")
    if close != -1 and close < end:
        start = close + 1
    else:
        match = re.match(r"\s*[A-Za-z0-9][A-Za-z0-9._-]*", entry)
        start = match.end() if match else 0
    while start < end and entry[start] == " ":
        start += 1
    return start, end


def _rewrite_specifiers(original, old, new):
    old_by_op = _versions_by_operator(old)
    new_by_op = _versions_by_operator(new)

    result = original
    for operator, new_versions in new_by_op.items():
        old_versions = old_by_op.get(operator)
        if not old_versions or len(old_versions) != len(new_versions):
            continue
        for old_version, new_version in zip(old_versions, new_versions):
            if old_version == new_version:
                continue
            pattern = re.compile(
                "(" + re.escape(operator) + r"\s*)" + re.escape(old_version)
                + r"(?![\w.*+-])"
            )
            result = pattern.sub(
                lambda m: m.group(1) + new_version, result, count=1
            )
    return result


def _versions_by_operator(specifier):
    grouped = {}
    for operator, version in SPECIFIER_RE.findall(specifier):
        grouped.setdefault(operator, []).append(version)
    return grouped


# --- helpers ----------------------------------------------------------------


def _same_group(key, group):
    return key == group or canonicalize_name(key) == canonicalize_name(group)


def _get(document, *keys):
    value = document
    for key in keys:
        if not hasattr(value, "get"):
            return None
        value = value.get(key)
        if value is None:
            return None
    return value


def _string_like(original, value):
    """A tomlkit string using the same quote style as ``original``."""
    literal = isinstance(original, String) and original.type in (
        StringType.SLL, StringType.MLL
    )
    multiline = isinstance(original, String) and original.type in (
        StringType.MLB, StringType.MLL
    )
    return tomlkit.string(value, literal=literal, multiline=multiline)
