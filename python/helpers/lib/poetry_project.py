"""Read a Poetry project the way Poetry itself does.

The helper loads ``pyproject.toml`` and ``poetry.lock`` through Poetry's own
project loader and lockfile reader, then reports what Poetry sees. Ruby makes
every policy decision; this module only exposes facts.

Poetry's loader and locker are internal APIs, not a stable public interface.
Every touch point is kept in this file so a Poetry upgrade only needs fixing
in one place.
"""

import json
from pathlib import Path

from poetry.core.version.markers import AnyMarker
from poetry.factory import Factory

# Locked from somewhere other than a package index, so the version on the
# requirement isn't meaningful to compare against.
DIRECT_SOURCE_TYPES = {"git", "directory", "file", "url"}


def parse_poetry_project(directory):
    # Poetry rejects some projects and lockfiles that older Poetry versions
    # accepted. Report that as a helper error so Ruby can choose a fallback.
    try:
        poetry = Factory().create_poetry(
            cwd=Path(directory), disable_plugins=True, disable_cache=True
        )
        locked = _locked_packages(poetry) if poetry.locker.is_locked() else []
        result = {
            "lock_version": _lock_version(poetry),
            "groups_and_markers_locked": (
                poetry.locker.is_locked_groups_and_markers()
            ),
            "declared": [
                _declared(dep) for dep in poetry.package.all_requires
            ],
            "locked": locked,
        }
    except Exception as e:
        # Exit non-zero, like parser.py, so Ruby raises HelperSubprocessFailed
        # and falls back instead of reading a nil result.
        print(json.dumps({"error": repr(e), "error_class": type(e).__name__}))
        exit(1)

    return json.dumps({"result": result})


def _lock_version(poetry):
    if not poetry.locker.is_locked():
        return None
    return poetry.locker.lock_data.get("metadata", {}).get("lock-version")


def _declared(dep):
    return {
        "name": dep.name,
        "pretty_name": dep.pretty_name,
        "constraint": dep.pretty_constraint,
        "groups": sorted(dep.groups),
        "markers": _marker_string(dep.marker),
        "extras": sorted(dep.extras),
        "optional": dep.is_optional(),
        "source": _source(
            dep.source_type,
            dep.source_url,
            dep.source_reference,
            dep.source_resolved_reference,
            dep.source_subdirectory,
            getattr(dep, "source_name", None),
        ),
        "git_ref": _git_ref(dep),
    }


def _git_ref(dep):
    # ``source_reference`` collapses tag, branch and rev into one value, but
    # callers only track git dependencies pinned to a tag.
    if not dep.is_vcs():
        return None
    return {"tag": dep.tag, "branch": dep.branch, "rev": dep.rev}


def _locked_packages(poetry):
    locker = poetry.locker
    repository_packages = locker.locked_repository().packages

    if locker.is_locked_groups_and_markers():
        info_by_key = {
            _key(pkg): info for pkg, info in locker.locked_packages().items()
        }
        walked_groups = {}
    else:
        info_by_key = {}
        walked_groups = _walk_groups(poetry.package, repository_packages)

    package_markers = {
        _key(pkg): _package_marker(info_by_key.get(_key(pkg)))
        for pkg in repository_packages
    }

    by_name = {}
    for pkg in repository_packages:
        by_name.setdefault(pkg.name, []).append(pkg)

    entries = []
    for pkg in repository_packages:
        info = info_by_key.get(_key(pkg))
        entries.append({
            "name": pkg.name,
            "pretty_name": pkg.pretty_name,
            "version": pkg.pretty_version,
            "optional": pkg.optional,
            "groups": (
                sorted(info.groups) if info
                else sorted(walked_groups.get(_key(pkg), []))
            ),
            "groups_from_lockfile": info is not None,
            "markers": (
                {g: _marker_string(m) for g, m in sorted(info.markers.items())}
                if info else None
            ),
            "source": _source(
                pkg.source_type,
                pkg.source_url,
                pkg.source_reference,
                pkg.source_resolved_reference,
                pkg.source_subdirectory,
            ),
            "dependencies": [
                _locked_dependency(pkg, req, by_name, package_markers)
                for req in pkg.requires
            ],
        })

    return entries


def _locked_dependency(parent, req, by_name, package_markers):
    """Link a locked package's requirement to the locked versions it can use.

    A child is linked when its version satisfies the requirement and the
    parent's marker, the requirement's marker, and the child's marker can all
    hold at once. This is what lets one ``requests`` version point at the
    ``urllib3`` 1.x it actually installs alongside, and another point at 2.x.
    """
    candidates = by_name.get(req.name, [])
    parent_marker = package_markers[_key(parent)]

    resolved = []
    for child in candidates:
        direct = child.source_type in DIRECT_SOURCE_TYPES
        if not direct and not req.constraint.allows(child.version):
            continue
        marker = (
            parent_marker
            .intersect(req.marker)
            .intersect(package_markers[_key(child)])
        )
        if marker.is_empty():
            continue
        resolved.append({"name": child.name, "version": child.pretty_version})

    # Never drop an edge: if marker or constraint filtering rules out every
    # candidate, the lockfile is likely stale, so link to all of them.
    if not resolved:
        resolved = [
            {"name": c.name, "version": c.pretty_version} for c in candidates
        ]

    return {
        "name": req.name,
        "constraint": req.pretty_constraint,
        "markers": _marker_string(req.marker),
        "extras": sorted(req.extras),
        "resolved": resolved,
    }


def _walk_groups(root, packages):
    """Work out groups for lockfiles older than 2.1, which don't record them.

    Starts at each group's declared dependencies and follows requirements
    through the lockfile by name. Markers are ignored, so a package reachable
    only on some platforms is still placed in the group.
    """
    by_name = {}
    for pkg in packages:
        by_name.setdefault(pkg.name, []).append(pkg)

    groups = {}
    for dep in root.all_requires:
        for group in dep.groups:
            queue = [dep.name]
            seen = set()
            while queue:
                name = queue.pop()
                if name in seen:
                    continue
                seen.add(name)
                for pkg in by_name.get(name, []):
                    groups.setdefault(_key(pkg), set()).add(group)
                    queue.extend(req.name for req in pkg.requires)
    return groups


def _package_marker(info):
    if info is None:
        return AnyMarker()
    return info.get_marker(info.groups)


def _key(pkg):
    return (pkg.name, pkg.pretty_version, pkg.source_type, pkg.source_url)


def _marker_string(marker):
    if marker is None or marker.is_any():
        return None
    return str(marker)


def _source(
    type_, url, reference, resolved_reference, subdirectory, name=None
):
    if type_ is None and name is None:
        return None
    return {
        "type": type_,
        "url": url,
        "reference": reference,
        "resolved_reference": resolved_reference,
        "subdirectory": subdirectory,
        "name": name,
    }
