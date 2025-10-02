# Dependency Graphers

Dependency graphers are used to convert a set of parsed dependencies into a data structure we can use to output the dependency graph of a project in a generic data structure based on GitHub's [Dependency submission API](https://docs.github.com/en/rest/dependency-graph/dependency-submission).

We will expect each language Dependabot supports to implement a `Dependabot::DependencyGraphers` class in future, but for now any modules that do not implement a specific class fail over to a 'best effort' generic implementation.

## Public API

Each `Dependabot::DependencyGraphers` class implements the following methods:

| Method                      | Description                                                                                   |
|-----------------------------|-----------------------------------------------------------------------------------------------|
| `.relevant_dependency_file` | Checks the list of `Dependabot::DependencyFile` objects assigned and determines which one the dependency list should be reported against. In most languages this will be the lockfile, if present, and the manifest otherwise. |
| `.resolved_dependencies`    | Processes the assigned `Dependabot::Dependency` objects into an informational hash |

An example of a `.resolved_dependencies` hash for a Bundler project:

```ruby
"addressable": {
  "package_url": "pkg:gem/addressable@2.8.6",
  "relationship": "indirect",
  "scope": "runtime",
  "dependencies": [],
  "metadata": {}
},
"ast": {
  "package_url": "pkg:gem/ast@2.4.2",
  "relationship": "indirect",
  "scope": "runtime",
  "dependencies": [],
  "metadata": {}
},
"aws-eventstream": {
  "package_url": "pkg:gem/aws-eventstream@1.3.0",
  "relationship": "indirect",
  "scope": "runtime",
  "dependencies": [],
  "metadata": {}
}
```

## Writing a dependency grapher for a new language

All new dependency graphers should inherit from `Dependabot::DependencyGraphers::Base` and
implement the following methods:

| Method                           | Description                                                                                   |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `.relevant_dependency_file`      | See Public API section. |
| `.fetch_subdependencies`         | Private method to fetch a list of package names, or PURLs, that are subdependencies of a given `Dependabot::Dependency`. It is expected that some languages will need to perform additional native commands to obtain this data. |
| `.purl_pkg_for`                  | Private method to map the given `Dependabot::Dependency` to the correct [Package-URL type](https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst) for the package manager involved. |

> [!WARNING]
> While PURLs are preferred in all languages for `.fetch_subdependencies`, for languages where multiple versions of a single dependency are permitted they _must_ be provided to be precise.

## Overriding file parser behaviour

In most cases, an ecosystem's file parser should provide us the dependency data we need to build the graph, but in some cases we may need to tweak this behaviour or experiment with alternative parsing strategies.

The `Dependabot::DependencyGraphers::Base` class provides the `prepare!` method as the hook that is called to generate the dependency list - if required this method can be redefined for a specific ecosystem to make
additional or alternative calls.
