## `dependabot-clojure`

Clojure support for [`dependabot-core`][core-repo]. It updates dependencies declared in:

- `project.clj` ([Leiningen][lein]): `:dependencies`, `:managed-dependencies`, `:plugins`, and the same keys inside `:profiles`. Repositories come from `:repositories` and `:plugin-repositories`
- `deps.edn` ([Clojure CLI][deps]): `:deps`, and `:deps`, `:extra-deps`, `:override-deps` and `:replace-deps` inside `:aliases`

This ecosystem is in beta. Repositories must set `enable-beta-ecosystems: true` in their `dependabot.yml`.

### How it works

- **Parsing:** a native helper in Clojure ([`helpers/`](helpers)) reads both files as data with [rewrite-clj][rewrite-clj]. It never evaluates them, so `project.clj` code doesn't run. For each dependency it returns the position of its version string, and the file updater rewrites only that string.
- **Versions:** Clojure dependencies are Maven artifacts. Versions are resolved from Maven Central and Clojars, plus any repository declared in `:repositories` (Leiningen) or `:mvn/repos` (deps.edn). This reuses the shared classes of the `maven` ecosystem.
- **Names** use the Maven format `group:artifact`, so `ring` becomes `ring:ring` and `org.clojure/clojure` becomes `org.clojure:clojure`. This matches GitHub security advisories.
- **Private registries:** `maven-repository` registries in `dependabot.yml` are used with their credentials. A registry with `replaces-base: true` replaces both Maven Central and Clojars.
- **Cooldown:** Clojars' directory listings have no dates, so release dates come from the POM's `Last-Modified` header.

Not updated:

- git and local dependencies
- versions that aren't string literals, such as `~version`
- the `RELEASE` and `LATEST` meta-versions, which already resolve to the newest release
- profile and alias declarations whose version differs from the top-level one, such as profiles that pin older Clojure versions for testing
- profiles outside `project.clj` (`profiles.clj`, `~/.lein/profiles.clj`) and classifiers in deps.edn (`lib$classifier`)

### Running locally

1. Start a development shell

   ```
   $ bin/docker-dev-shell clojure
   ```

2. Run tests

   ```
   [dependabot-core-dev] ~ $ cd clojure && rspec
   ```

The helper jar is built in the image (see [`Dockerfile`](Dockerfile)). After changing the helper, rebuild it with `bin/docker-dev-shell clojure --rebuild`.

[core-repo]: https://github.com/dependabot/dependabot-core
[lein]: https://leiningen.org
[deps]: https://clojure.org/reference/deps_edn
[rewrite-clj]: https://github.com/clj-commons/rewrite-clj
