"""Re-lock a Poetry project the way ``poetry update <names> --lock`` does.

Only the named packages are re-resolved. Every other package keeps its
locked version because the solver is given the existing lockfile as its
locked repository, which is what ``poetry update`` does too.

Ruby writes the (prepared) ``pyproject.toml`` and ``poetry.lock`` into
``directory`` and sets up credentials as ``POETRY_HTTP_BASIC_*`` environment
variables before calling this. The helper never reads credentials itself.

``pins`` steer packages that are locked at several versions, one per
marker. Ruby picks a target for each locked version and passes it with that
version's groups and markers. Each pin is added to the root package in
memory as ``name==version ; marker`` in its group, which makes Poetry's
solver fork per marker the same way it does for a multiple-constraints
declaration. ``pyproject.toml`` isn't changed.

Like ``poetry_project.py``, this relies on Poetry internals (``Installer``,
``Locker``), so every touch point is kept in this file.
"""

import json
import os
from pathlib import Path

from cleo.io.null_io import NullIO
from packaging.utils import canonicalize_name
from poetry.core.packages.dependency import Dependency
from poetry.core.packages.dependency_group import DependencyGroup
from poetry.core.version.markers import parse_marker
from poetry.factory import Factory
from poetry.installation.installer import Installer
from poetry.puzzle.exceptions import SolverProblemError
from poetry.repositories.installed_repository import InstalledRepository
from poetry.utils.env import NullEnv


class PackageNotInProjectError(Exception):
    pass


class InvalidPinError(Exception):
    pass


def relock_poetry_project(directory, package_names, pins=None):
    try:
        result = _relock(Path(directory), package_names, pins or [])
    except SolverProblemError as e:
        # Kept apart from other failures so Ruby can map it to a
        # resolvability error without matching on the message.
        _exit_with_error(e, "SolverProblemError")
    except Exception as e:
        _exit_with_error(e, type(e).__name__)

    return json.dumps({"result": result})


def _relock(directory, package_names, pins):
    # Matches the shell path, which runs `poetry config system-git-client
    # true` first. Must be set before Poetry reads its config.
    os.environ["POETRY_SYSTEM_GIT_CLIENT"] = "true"

    poetry = Factory().create_poetry(cwd=directory, disable_plugins=True)
    names = [canonicalize_name(n) for n in package_names]
    _check_names(poetry, names)
    _add_pins(poetry.package, names, pins)

    installer = Installer(
        NullIO(),
        # The solver doesn't evaluate markers against this env when locking.
        # It's only used for installs, which `execute_operations(False)`
        # turns off.
        NullEnv(),
        poetry.package,
        poetry.locker,
        poetry.pool,
        poetry.config,
        # A fresh environment, like the throwaway venv `poetry update` makes.
        installed=InstalledRepository(),
        disable_cache=poetry.disable_cache,
        build_constraints=poetry.build_constraints,
    )
    # Same calls as `poetry update <names> --lock`: update only the
    # whitelisted packages, keep the rest at their locked versions, and
    # write the lockfile without installing.
    installer.whitelist(names)
    installer.execute_operations(False)
    installer.update(True)
    status = installer.run()
    if status != 0:
        raise RuntimeError(f"Poetry installer exited with status {status}")

    # newline="" keeps CRLF lockfiles as Poetry wrote them.
    with open(poetry.locker.lock, encoding="utf-8", newline="") as f:
        content = f.read()
    return {
        "lockfile": content,
        "versions": _locked_versions(poetry, names),
    }


def _check_names(poetry, names):
    # `poetry update` refuses names that are neither declared nor locked.
    known = {dep.name for dep in poetry.package.all_requires}
    if poetry.locker.is_locked():
        known |= {
            p.name for p in poetry.locker.locked_repository().packages
        }
    missing = [n for n in names if n not in known]
    if missing:
        raise PackageNotInProjectError(
            "The following packages are not dependencies of this project: "
            + ", ".join(missing)
        )


def _add_pins(package, names, pins):
    for pin in pins:
        name = canonicalize_name(pin["name"])
        if name not in names:
            # A pin on a package that isn't re-resolved would be ignored,
            # because the solver takes it from the locked repository.
            raise InvalidPinError(f"{pin['name']} is pinned but not updated")
        markers = pin.get("markers") or {}
        if not markers:
            raise InvalidPinError(f"{pin['name']} pin has no groups")
        for group, marker in markers.items():
            dependency = Dependency(
                pin["name"], f"=={pin['version']}", groups=[group]
            )
            if marker:
                dependency.marker = parse_marker(marker)
            if not package.has_dependency_group(group):
                package.add_dependency_group(DependencyGroup(group))
            package.dependency_group(group).add_dependency(dependency)


def _locked_versions(poetry, names):
    # Writing the lockfile clears the locker's cached data, so this reads
    # what Poetry just wrote. A package can be locked at several versions
    # (one per marker), so every version is returned.
    versions = {name: [] for name in names}
    for pkg in poetry.locker.locked_repository().packages:
        if pkg.name in versions:
            versions[pkg.name].append(pkg.pretty_version)
    return versions


def _exit_with_error(error, error_class):
    # str() keeps Poetry's message text intact for Ruby's error regexes;
    # repr() would escape quotes and newlines.
    message = str(error) or repr(error)
    print(json.dumps({"error": message, "error_class": error_class}))
    exit(1)
