## `dependabot-pub`

Dart (pub) support for [`dependabot-core`][core-repo].

### Limitations

 - Limited updating of git-dependencies
   * `dart pub` in general doesn't read versions numbers from git, so upgrade logic is limited to upgrading to what the 'ref' is pointing to.
   * If you pin to a specific revision in `pubspec.yaml` dependabot will not find upgrades.
   * If you give a branch in `pubspec.yaml` dependabot will upgrade to the
     latest revision that branch is pointing to, and update `pubspec.lock`
     accordingly.
 - Security updates currently bump to the latest version. If the latest version is vulnerable, no update will happen (even if an earlier version could be used). Changing the upgrade strategy to use the minimum non-vulnerable version is tracked in https://github.com/dependabot/dependabot-core/issues/5391.
 - If the version found is ignored (by dependabot config) no update will happen (even if an earlier version could be used)
 - Limited metadata support (just retrieves the repository link).
 - No support for auhtentication of private package repositories (mostly a configuration issue).
 - `updated_dependencies_after_full_unlock` only allows updating to a later version, if the latest version that is mutually compatible with other dependencies is the latest version of the said package. This is a dependabot limitation.

### Running locally

1. Install Ruby dependencies
   ```
   $ bundle install
   ```

2. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Dependency Service Interface

The `dart pub` repo offers an experimental dependency services interface which
allows checking for available updates.

It is implemented as helpers/bin/dependency_services.dart, that is mainly a wrapper around the implementation in the [pub client](https://github.com/dart-lang/pub).

#### List Dependencies

```js
# dart pub global run pub:dependency_services list
{
  "dependencies": [
    // For each dependency:
    {
      "name": "<package-name>",
      "version": "<version>",

      "kind": "direct" || "dev" || "transitive",
      "source": <source-info>

      // Version constraint, as written in `pubspec.yaml`, null for
      // transitive dependencies.
      "constraint": "<version-constraint>" || null,
    },
    ... // must contain an entry for each dependency!
  ],
}

```

#### Dependency Report

```js
# dart pub global run pub:dependency_services report
// TODO: We likely need to provide ignored versions on stdin
{
  "dependencies": [
    // For each dependency:
    {
      "name":        "<package-name>",       // name of current dependency
      "version":     "<version>",            // current version
      "kind":        "direct" || "dev" || "transitive",
      "source": <source-info>
      "constraint":  "<version-constraint>" || null, // null for transitive deps

      // Latest desirable version of the current dependency,
      //
      // Various heuristics defining "desirable" may apply.
      // For Dart we ignore pre-releases, unless the current version of the
      // dependency is already a pre-release.
      "latest": "<version>",

      // In the following possible upgrades are listed for different
      //
      // The constraints are given in three versions, according to different
      // strategies for updating constraint to allow the new version of a
      // package:
      //
      // * "constraintBumped": always update the constraint lower bound to match
      //   the new version.
      // * "constraintBumpedIfNeeded": leave the constraint if the original
      //   constraint allows the new version.
      // * "constraintWidened": extend only the upper bound to include the new
      //   version.

      // If it is possible to upgrade the current version without making any
      // changes in the project manifest, then this lists the set of upgrades
      // necessary to get the latest possible version of the current dependency
      // without changes to the project manifest.
      //
      // The set of changes here should aim to avoid unnecessary changes.
      // That is in order of preference (heuristics allowed):
      //  * Always avoid any changes to project manifest,
      //  * Upgrade current dependency to latest version possible,
      //  * Remove unnecessary transitive dependencies,
      //  * Avoid changes to other dependencies when possible.
      //
      // This can involve breaking version changes for transitive dependencies.
      // But a breaking change for a direct-dependency is only possible if allowed by
      // the manifest.
      "compatible": [
        {
           "name":                     "<package-name>",
           "version":                  "<new-version>" || null, // null, if removed
           "kind":                     "direct" || "dev" || "transitive",
           "source": <source-info>
           "previousSource": <source-info>
           "constraintBumped":         "<version-constraint>" || null, // null, if transitive
           "constraintBumpedIfNeeded": "<version-constraint>" || null, // null, if transitive
           "constraintWidened":        "<version-constraint>" || null, // null, if transitive
           "previousVersion":    "<version>" || null, // null, if added
           "previousConstraint": null, // always 'null' in compatible solution
        },
        ...
      ],

      // If it is possible to upgrade the current version without making changes
      // to other dependencies in the project manifest, then this lists the set
      // of upgrades necessary to get the latest possible version of the current
      // dependency without changes to other packages in the project manifest.
      //
      // The set of changes here should aim to avoid unnecessary changes.
      // That is in order of preference (heuristics allowed):
      //  * Always avoid changes to other dependencies in project manifest,
      //  * Upgrade the current dependency to latest version possible,
      //  * Remove unnecessary transitive dependencies,
      //  * Avoid changes to other dependencies when possible.
      //
      // This can involve breaking version changes for the current dependency.
      // It can also involve breaking changes for transitive dependencies. But
      // changes for direct-dependencies are only possible if the manifest allows them.
      "singleBreaking": [
        {
           "name":                     "<package-name>",
           "version":                  "<new-version>" || null, // null, if removed
           "kind":                     "direct" || "dev" || "transitive",
           "source": <source-info>
           "previousSource": <source-info>
           "constraintBumped":         "<version-constraint>" || null, // null, if transitive
           "constraintBumpedIfNeeded": "<version-constraint>" || null, // null, if transitive
           "constraintWidened":        "<version-constraint>" || null, // null, if transitive
           "previousVersion":          "<version>" || null, // null, if added
           "previousConstraint":       "<version-constraint>" || null, // null, if transitive
        },
        ...
      ],

      // If it is possible to upgrade the current version of the current
      // dependency by allowing multiple changes project manifest, then this
      // lists the set of upgrades necessary to get the latest possible version
      // of the current dependency, without removing any direct-dependencies.
      //
      // The set of changes here should aim to avoid unnecessary changes.
      // That is in order of preference (heuristics allowed):
      //  * Always avoid removing direct-/dev-dependencies from project manifest.
      //  * Upgrade the current dependency to latest version possible,
      //  * Avoid changes to other dependencies in project manifest when
      //    possible,
      //  * Remove unnecessary transitive dependencies,
      //  * Avoid changes to other dependencies when possible.
      //
      // This can involve breaking changes for any dependency.
      "multiBreaking": [
        {
           "name":                     "<package-name>",
           "version":                  "<new-version>" || null, // null, if removed
           "kind":                     "direct" || "dev" || "transitive",
           "source": <source-info>
           "previousSource": <source-info>
           "constraintBumped":         "<version-constraint>" || null, // null, if transitive
           "constraintBumpedIfNeeded": "<version-constraint>" || null, // null, if transitive
           "constraintWidened":        "<version-constraint>" || null, // null, if transitive
           "previousVersion":          "<version>" || null, // null, if added
           "previousConstraint":       "<version-constraint>" || null, // null, if transitive
        },
        ...
      ],
    },
    ... // must contain an entry for each dependency!
  ],
}
```

#### Applying Changes

```js
# dart pub global run pub:dependency_services apply << EOF
{  // Write on stdin:
   "dependencyChanges": [
      {
         "name":            "<package-name>",
         "version":         "<new-version>",
         "constraint":      "<version-constraint>" or null,
         "source": <source-info>
      },
      ...
   ],
}
# EOF
{ // Output:
  "dependencies": [],
}
# Modifies pubspec.yaml and pubspec.lock on disk
```


The <source-info> is either `null` (no information provided) or a map providing
details about the package source in a manner specific to the
package-environment.

For a git dependency it will usually contain the git-url,
the path inside the repo and the ref. For a repository package it would contain
the url of the repository.
```js
{
  "type": "git" || "hosted" || "path" || "sdk", // Name of the source.
  ... // Other keys are free form json information about the dependency
}
```
## Detection of Flutter and Dart SDK versions.

`dependency_services` should be run in the context of the right Flutter and
Dart SDK versions as these will affect package resolution.

The pub dependabot integration supports the flutter releases on the `stable` and
`beta`
[channel](https://github.com/flutter/flutter/wiki/Flutter-build-release-channels).
Each Flutter release comes with a matching Dart release.

The `helpers/bin/infer_sdk_versions.dart` script will parse the root pubspec, and
try to determine the right release based on the SDK constraints and the list of
available releases:

* The latest stable release that matches the SDK constraints will be chosen
* If there is no stable release it will choose the newest beta that matches the
SDK constraints.
