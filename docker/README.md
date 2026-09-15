## `dependabot-docker`

Docker support for [`dependabot-core`][core-repo].

**Note:** The `docker_compose` ecosystem in this directory lives under `docker/lib/dependabot/docker_compose/` with specs under `docker/spec/dependabot/docker_compose/`, to share common code while maintaining separate package management.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell docker
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd docker && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Supported tag schemas

Dependabot supports updates for Docker tags that use semver versioning, dates, and build numbers.
The Docker tag class is located at:
https://github.com/dependabot/dependabot-core/blob/main/docker/lib/dependabot/docker/tag.rb

#### Semver

Dependabot will attempt to parse a semver version from a tag and will only update it to a tag with a matching prefix and suffix.

As an example, `base-12.5.1` and `base-12.5.1-golden` would be parsed as `<prefix>-<version>` and `<prefix>-<version>-<suffix>` respectively.

That means for `base-12.5.1` only another `<prefix>-<version>` tag would be a viable update, and for `base-12.5.1-golden`, only another `<prefix>-<version>-<suffix>` tag would be viable. The exception to this is if the suffix is a SHA, in which case it does not get compared and only the `<prefix>-<version>` parts are considered in finding a viable tag.

#### Dates

Dependabot will parse dates in the `yyyy-mm`, `yyyy-mm-dd` formats (or with `.` instead of `-`) and update tags to the latest date.

As an example, `2024-01` will get updated to `2024-02` and `2024.01.29` will get updated to `2024.03.15`.

#### Build numbers

Dependabot will recognize build numbers and will update to the highest build number available.

As an example, `21-ea-32`, `22-ea-7`, and `22-ea-jdk-nanoserver-1809` are mapped to `<version>-ea-<build_num>`, `<version>-ea-<build_num>`, and `<version>-ea-jdk-nanoserver-<build_num>` respectively.
That means only "22-ea-7" will be considered as a viable update candidate for `21-ea-32`, since it's the only one that respects that format.

### Cooldown publication dates

Cooldown uses only registry-assigned publication timestamps, not dates that an image publisher can supply or backdate. Docker Hub's `tag_last_pushed` is currently the only accepted source.

- **Docker Hub:** Dependabot reads `tag_last_pushed` from the tag metadata API. Pushing a tag again can restart its cooldown. A reported digest must match the resolved manifest digest. Legacy responses that omit the digest or return `null` are accepted only when every requirement is unpinned and automatic digest pinning is disabled.
- **GitHub Container Registry (GHCR):** Cooldown publication dates are unavailable. GitHub Packages `updated_at` has not been established as the publication time of the relevant tag or digest, so Dependabot does not use it or query that API for cooldown. Normal GHCR dependency updates remain supported.
- **Other registries:** Publication dates remain unavailable until a registry-assigned timestamp source and its semantics are verified.

Generic `Last-Modified` headers, image-config `created`, OCI creation annotations, package-version `created_at`, and local first-seen times are not cooldown date sources. Missing, conflicting, or unusable metadata never falls back to one of these dates. An old child-manifest header cannot establish the publication age of a new multi-platform index.

Existing and newly introduced digest pins require an exact metadata match. For a multi-platform index, matching one child is insufficient. Dependabot retains the checked digest when generating the update, even if the tag moves during the check. Unpinned tags remain mutable after the check, so their cooldown cannot guarantee the age of the image eventually pulled.

The registry operator is a trust boundary: registry dates cannot protect against an attacker-operated or compromised registry. Adding a source requires establishing that publishers cannot choose or backdate its timestamps, that the timestamp describes the relevant publication, and that hosted authentication works. New pushes, repushes, and retagging existing digests must be covered; successful mocked API responses alone do not establish those guarantees.

When no verified publication date is available, Dependabot retains its existing policy: allow the update and record a `cooldown_date_unavailable` warning. This avoids using an untrusted date but does not guarantee that every update waits through cooldown. Requiring that guarantee would need a separate policy to hold updates with unavailable dates.
