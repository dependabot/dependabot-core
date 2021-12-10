## `dependabot-pub`

Dart (pub) support for [`dependabot-core`][core-repo].

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

#### List Dependencies

```js
# dart global run pub:dependency_services list
{
  "dependencies": [
    // For each dependency:
    {
      "name": "<package-name>",
      "version": "<version>",

      "kind": "direct" || "dev" || "transitive",

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
# dart global run pub:dependency_services report
// TODO: We likely need to provide ignored versions on stdin
{
  "dependencies": [
    // For each dependency:
    {
      "name":        "<package-name>",       // name of current dependency
      "version":     "<version>",            // current version
      "kind":        "direct" || "dev" || "transitive",
      "constraint":  "<version-constraint>" || null, // null for transitive deps

      // Latest desirable version of the current dependency,
      //
      // Various heuristics defining "desirable" may apply.
      // For Dart we ignore pre-releases, unless the current version of the
      // dependency is already a pre-release.
      "latest": "<version>",

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
           "name":            "<package-name>",
           "version":         "<new-version>" || null, // null, if removed
           "kind":            "direct" || "dev" || "transitive",
           "constraint":      "<version-constraint>" || null, // null, if transitive

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
           "name":            "<package-name>",
           "version":         "<new-version>" || null, // null, if removed
           "kind":            "direct" || "dev" || "transitive",
           "constraint":      "<version-constraint>" || null, // null, if transitive

           "previousVersion":    "<version>" || null, // null, if added
           "previousConstraint": "<version-constraint>" || null, // null, if transitive
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
           "name":            "<package-name>",
           "version":         "<new-version>" || null, // null, if removed
           "kind":            "direct" || "dev" || "transitive",
           "constraint":      "<version-constraint>" || null, // null, if transitive

           "previousVersion":    "<version>" || null, // null, if added
           "previousConstraint": "<version-constraint>" || null, // null, if transitive
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
# dart global run pub:dependency_services apply << EOF
{  // Write on stdin:
   "dependencyChanges": [
      {
         "name":            "<package-name>",
         "version":         "<new-version>",
         "constraint":      "<version-constraint>" or null,
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
