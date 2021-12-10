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

The `dart pub` client offers an experimental dependency services interface which
allows checking for available updates.

#### List Dependencies

```js
# dart pub __experimental-dependency-services list
{
  "dependencies": [
    // For each dependency:
    {
      "name": "<package-name>",
      "version": "<version>",

      "kind": "direct" || "dev" || "transitive",

      // Version constraint, as written in `pubspec.yaml`, omitted for
      // transitive dependencies.
      "constraint": "<version-constraint>",
    },
    ... // must contain an entry for each dependency!
  ],
}
```

#### Dependency Report

```js
# dart pub __experimental-dependency-services
{
  "dependencies": [
    // For each dependency:
    {
      "name":        "<package-name>",       // name of current dependency
      "version":     "<version>",            // current version
      "kind":        "direct" || "dev" || "transitive",
      "constraint":  "<version-constraint>", // omitted for transitive deps

      // Latest version of the current dependency, ignoring pre-releases, unless
      // current version is a pre-release.
      "latest": "<version>",

      // If it is possible to upgrade the current version without making any
      // changes in the project manifest, then this lists the set of upgrades
      // necessary to get the latest possible version of the current dependency
      // without changes to project manifest.
      //
      // The set of changes here should aim to avoid unnecessary changes.
      // That is in order of preference (heuristics allowed):
      //  * Always avoid any changes to project manifest,
      //  * Upgrade current dependency to latest version possible,
      //  * Remove unnecessary transitive dependencies,
      //  * Avoid changes to other dependencies when possible.
      //
      // This can involve breaking version changes for transitive dependencies.
      // But breaking changes for direct-dependencies is only possible if the
      // manifest allows this.
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
      // dependency without changes to other packages in project manifest.
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
      // breaking changes for direct-dependencies is only possible if the
      // manifest allows this.
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
# dart pub __experimental-dependency-services apply << EOF
{  // Write on stdin:
   "dependencyChanges": [
      {
         "name":            "<package-name>",
         "version":         "<new-version>",
         "constraint":      "<version-constraint>",
      },
      ...
   ],
}
# EOF
{ // Output:
  "dependencies": [
    // For each dependency: (even ones not changed)
    {
      // Same as in list-dependencies:
      "name":     "<package-name>",     // name of current dependency
      "version":  "<version>" || null,  // current version, null if removed!
      "kind":     "direct" || "dev" || "transitive",

      // What was the previous version, same as "version" if no change!
      "previous": "<version>",

      // Link to changelog
      "changelog": "https://...",

      // List of changelog entries from "version" to "previous" version.
      "changes": [
        {
          "version": "<version>",
          "section": "<markdown>",
        },
        ...
      ],

      // TODO: other meta-data fields like something to find commits...
    },
    ... // must contain an entry for each dependency!
  ],
}
```
