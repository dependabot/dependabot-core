# Feedback and contributions to Dependabot

👋 Want to give us feedback on Dependabot, or contribute to it? That's great - thank you so much!

By submitting a contribution, you agree that contribution is licensed to GitHub under the [MIT license](LICENSE).

#### Overview

- [Contribution workflow](#contribution-workflow)
- [Building with Nix](#building-with-nix)
- [Project layout](#project-layout)
- [How to structure your Git Commits](#how-to-structure-your-git-commits)
- [Contributing new ecosystems](#contributing-new-ecosystems)

## Contribution workflow

1. Fork the project.
2. Get the [development environment running](README.md#getting-a-development-environment-running).
3. Make your feature addition or bug fix.
4. Add [tests for it](README.md#running-tests). This is important so we don't break it in a future version unintentionally.
5. Ensure your code is well-documented and easy to understand.
6. Send a pull request. The tests will run on it automatically, so don't worry if you couldn't get them running locally.
7. If you are helping bump a version or add new ecosystem support to Dependabot, please file a corresponding PR for the change in the [GitHub docs repo](https://docs.github.com/en/contributing/collaborating-on-github-docs/about-contributing-to-github-docs). The list of supported package manager versions lives [here](https://github.com/github/docs/blob/main/data/reusables/dependabot/supported-package-managers.md). The rest of the Dependabot docs are primarily in [this directory](https://github.com/github/docs/tree/main/content/code-security/dependabot) and [this directory](https://github.com/github/docs/tree/main/data/reusables/dependabot).

## Project layout

There's a good description of the project's layout in our [README's Architecture section](README.md#architecture-and-code-layout), but if you're
struggling to understand how anything works please don't hesitate to create an issue.

## Building with Nix

Dependabot container images can be built using [Nix](https://nixos.org/) and [nix2container](https://github.com/nlewo/nix2container) as an alternative to Docker. Nix builds are reproducible, pin every dependency to an exact version, and avoid the need to manage PPAs or manually-installed packages.

### Prerequisites

Install Nix with flakes support:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh
```

Docker is still required to run the built images locally.

### Building images

```bash
# Build and load the core image
cd nix && nix build .#packages.x86_64-linux.core --no-link
nix run .#packages.x86_64-linux.core.copyToDockerDaemon

# Build and load an ecosystem image (e.g., go_modules)
nix build .#packages.x86_64-linux.ecosystems.go_modules --no-link
nix run .#packages.x86_64-linux.ecosystems.go_modules.copyToDockerDaemon
```

Or use the build script with the `USE_NIX` flag:

```bash
USE_NIX=1 script/build go_modules
```

### Development shell

```bash
USE_NIX=1 bin/docker-dev-shell go_modules
```

### macOS contributors

Nix on macOS cannot build Linux container images natively. macOS contributors should either:

1. **Pull pre-built images** from GHCR (recommended): `docker pull ghcr.io/dependabot/dependabot-updater-gomod`
2. **Set up a Linux builder**: Use a Linux VM or remote builder for Nix builds. See the [Nix remote builds documentation](https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html).

### Bumping dependency versions

- **Single tool** (e.g., Go): Edit `nix/ecosystems/go_modules.nix` and change `pkgs.go_1_26` to the new version attribute.
- **All system packages**: Run `cd nix && nix flake update nixpkgs` and commit the updated `flake.lock`.

## How to structure your Git Commits

1. Commit messages matter. [Here's how to write them well](https://cbea.ms/git-commit/).
2. We ask for one-commit-per-logical change. This generally results in one-commit-per-PR, but it's okay if a PR contains
   multiple commits when it's easier to understand each commit as a distinct unit of work, but they must all be landed together.
   A general rule of thumb is "What will make this code change simplest to understand for someone `git blame` spelunking down the road?"
3. Because of ☝️ we will generally merge-via-squash. However, if a PR contains multiple commits that shouldn't be squashed, then we will typically merge via a merge commit and not a rebase since merge-via-rebase can break `git bisect`.

## Contributing new ecosystems

If you are an ecosystem maintainer and are interested in integrating with Dependabot, and are willing to help provide the expertise necessary to build and support it, please see our [new ecosystems guide](https://github.com/dependabot/dependabot-core/blob/main/NEW_ECOSYSTEMS.md) for detailed information on the requirements and process.

### What's next?

In `dependabot-core`, each ecosystem implementation is in its own gem so you can use Dependabot for a language
we have not merged by creating a [script](https://github.com/dependabot/dependabot-script) to run your own gem or
fork of core, e.g. [dependabot-lein-runner](https://github.com/CGA1123/dependabot-lein-runner)

We are investing more developer time directly in `dependabot-core` to improve our architecture so that
each ecosystem is more isolated and testable. Our goal is make it easier to create and test Dependabot extensions so there is a paved path for running additional
ecosystems in the future.

## Stalebot

We have begun using a [Stalebot action](https://github.com/actions/stale) to help keep the Issues and Pull requests backlogs tidy. You can see the configuration [here](.github/workflows/stalebot.yml). If you'd like to keep an issue open after getting a stalebot warning, simply comment on it and it'll reset the clock.
