# GHCR cooldown timestamp investigation

**Status:** Draft investigation and design discussion. No implementation or policy
change is proposed for approval yet.

Related: [Docker cooldown issue #16114](https://github.com/dependabot/dependabot-core/issues/16114)
and [Docker Hub cooldown PR #16143](https://github.com/dependabot/dependabot-core/pull/16143).
This investigation is independent of the Docker Hub implementation.

## Summary

GitHub Packages exposes `created_at` and `updated_at` on the package-version
record associated with a GHCR manifest digest. A controlled experiment found:

- Newly registered manifests and multi-platform indexes received current
  package-version timestamps despite deliberately backdated image metadata.
- Repushing the same digest, adding a tag, and moving a tag back to an existing
  digest did not advance either timestamp.
- A new parent index received its own timestamps, even when its child manifests
  already existed.

Consequently, `updated_at` must not be treated as an equivalent of Docker Hub's
`tag_last_pushed`. Digest and tag matching do not repair the timestamp's semantics.
The package-version `created_at` is a candidate for **exact-digest age**, not
**time since the tag's latest push or assignment**.

These are observations of current behavior, not a provider guarantee of
immutability, visibility history, or behavior across all package lifecycle events.
This document does not add a GHCR fallback or change missing-date behavior.

## Controlled experiment

The experiment ran on 2026-09-17 in a uniquely named disposable GHCR package owned
by `dsp-testing`, using a GitHub Actions workflow in
`dsp-testing/dependabot-all-updates-test-staging`.

- [Workflow run](https://github.com/dsp-testing/dependabot-all-updates-test-staging/actions/runs/35213101408)
- [Probe source at the executed revision](https://github.com/dsp-testing/dependabot-all-updates-test-staging/blob/fb4fff2b6ea390eaf214bf934a51cfce3cc79550/.github/scripts/ghcr_cooldown_probe.py)
- [Raw observations at an immutable commit](https://github.com/dsp-testing/dependabot-all-updates-test-staging/blob/3b2733a9ebf7cce42aab5640354146978af16594/ghcr-cooldown-probe-results.json)

The staging links require repository access; the relevant measurements are
summarized below.

The probe uploaded synthetic, zero-layer OCI images. Their config `created`,
creation labels, and manifest/index creation annotations were set to
`2000-01-01T00:00:00Z`. No existing package or production image was modified.
For each publication, the probe verified the exact tag and digest through
registry requests, then polled package-version metadata approximately every five
seconds for at least 30 seconds. The full run continued observing the older
records through `11:00:55 UTC`.

The identifiers below refer to exact manifest or index digests, not config blobs:

| Identifier | Digest |
| --- | --- |
| A, amd64 image | `sha256:ce8a02457313ca0b996674712b5d02f2a028fc4f5091b8e69fe36bcf16e36594` |
| B, arm64 image | `sha256:5bee584a56573c547b00264309fb5b62230acc5bf70324117815d3630481c68a` |
| I1, index of A and B | `sha256:bf88c9fe35758563dbf7491abba342c0f54015256ca3aaf0fcf6f0b88cec6b72` |
| I2, same children, changed index annotation | `sha256:69f0b987feaf905f9f7fe209ac2a0674239aa77f2219b7512e559ed0062aa638` |

All times in the following table are UTC on 2026-09-17. The operation time is the
`Date` header returned by a successful manifest PUT. It timestamps this controlled
experiment only and is not a proposed publication-date source. The last two
columns are package-version API fields for the target digest.

| Operation | Target | Operation time | `created_at` | `updated_at` |
| --- | --- | --- | --- | --- |
| Initial push of `probe`, with backdated creation metadata | A | 10:56:56 | 10:56:56 | 10:56:56 |
| Repush the same tag and digest | A | 10:57:30 | 10:56:56 | 10:56:56 |
| Add `alias` to the existing digest | A | 10:58:04 | 10:56:56 | 10:56:56 |
| Move `probe` to a newly uploaded digest | B | 10:58:39 | 10:58:39 | 10:58:39 |
| Move `probe` back to the older digest | A | 10:59:13 | 10:56:56 | 10:56:56 |
| Publish `multi` using the two existing child images | I1 | 10:59:47 | 10:59:47 | 10:59:47 |
| Change `multi` to a new index with the same children | I2 | 11:00:21 | 11:00:21 | 11:00:21 |

The API's tag lists reflected each reassignment while the older records' dates
remained unchanged. This rules out relying on `updated_at` to restart cooldown
for every tag assignment. The initial upload also demonstrates that backdating
image metadata did not backdate these package records in this experiment.

The successful run deleted its disposable package (`204`) and verified absence
with an authenticated package lookup (`404`). The temporary workflow was removed;
probe source and results were retained on the isolated staging branch.
Fifteen local tests validated the probe's scoping, digest checks, observation
handling, and cleanup. They are tests of the experimental harness, not a GHCR
cooldown implementation.

## Policy options

### Option A: exact-digest age

Measure how long the package-version record for the exact proposed manifest or
index digest has existed, using its registry-managed `created_at`.

This would delay newly registered content, including new indexes built from old
children. It would not restart a delay when already registered content is
repushed or assigned a different tag. A publisher could register content in
advance, wait, and attach a release tag later.

Digest age is therefore not tag age, time since public availability, or evidence
that an image has been reviewed. This distinction must be explicitly accepted
and documented before implementation.

If this policy is selected, a candidate design would:

1. Resolve and retain the proposed manifest/index digest.
2. Find that exact package-version record in the correct GHCR owner/package.
   Confirm the requested tag belongs to it when resolving a tagged reference.
3. Validate its `created_at` and apply the configured cooldown.
4. Generate the update using the same checked digest.

An old child-manifest date must never stand in for a new parent index.
Existing pins, newly added pins, digest-only references, and unversioned tags
need explicit treatment. A guarantee about the image eventually pulled requires
digest pinning; an unpinned tag can move after the check. Automatically adding
pins would itself require an explicit behavior decision.

### Option B: tag-push or tag-assignment age

Require a delay after the target tag's most recent push or assignment, including
assignment to an older digest.

Neither measured API field provides this clock. Supporting this policy needs a
registry-provided tag event timestamp with defined semantics, or a separately
designed observation service and policy. A locally observed time would measure
observation, not registry publication, and is not a fallback proposed here.

Do not substitute image-config `created`, OCI creation annotations, generic HTTP
headers, GitHub Release dates, or package-level dates for the missing tag clock.

## Authentication and API integration

The [Packages REST API](https://docs.github.com/en/rest/packages/packages#list-package-versions-for-a-package-owned-by-an-organization)
lists container package versions under organization and user endpoints. Responses
include the version name, `created_at`, `updated_at`, and container tags.

In live access checks, anonymous package-version listing returned `401`; the
local OAuth token returned `403` without `read:packages`. Public GHCR image pulls
can be anonymous, but that does not imply anonymous access to the metadata API.
The controlled workflow could read its own linked package using its
`GITHUB_TOKEN`; that does not establish access to arbitrary third-party packages.

Any implementation must validate hosted credential-proxy support for requests
to `api.github.com`, not assume credentials used for `ghcr.io` pulls are sufficient.
Secrets must remain in the proxy. Owner/package names, nested package paths,
pagination without an arbitrary cutoff, and denied access need explicit handling.

See [GitHub's package permissions documentation](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages).

## Open questions and acceptance criteria

Before a production implementation:

- Choose digest age or tag-assignment age; do not silently change the meaning of
  cooldown by treating them as equivalent.
- Obtain a provider contract, or explicitly document the supported empirical
  behavior and its limits, for timestamp provenance and record lifecycle.
- Test deletion and restoration, namespace/package migration, and private-to-public
  visibility changes. The experiment did not cover these. GitHub documents
  [package restoration](https://docs.github.com/en/packages/learn-github-packages/deleting-and-restoring-a-package)
  but does not define its timestamp behavior.
- Verify hosted authentication for organization-owned, user-owned, public,
  private, and cross-repository packages, including permission failures.
- Decide whether missing, invalid, stale, or conflicting metadata permits an
  update with a warning or holds it. Rejecting an untrusted timestamp is not the
  same as enforcing a minimum age on every update.
- Add public-path regression coverage for version updates, same-tag digest
  changes, pure digest references, multi-platform indexes, pinning, and tag
  movement between checking and writing.
- Test exact cooldown boundaries, zero/default/semver-specific windows,
  include/exclude rules, pagination, rate limits, and malformed responses.
- Run end-to-end jobs through `script/dependabot` with verified registry dates and
  digest identities, rather than treating successful mocked API calls as proof
  of registry semantics.

The recommended next step is to review the policy choice and close the
authentication/lifecycle gaps. Do not restore the earlier `updated_at` fallback
as a tag-push timestamp.
