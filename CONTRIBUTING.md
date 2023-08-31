# Feedback and contributions to Dependabot

👋 Want to give us feedback on Dependabot, or contribute to it? That's great - thank you so much!

#### Overview

- [Contribution workflow](#contribution-workflow)
- [Project layout](#project-layout)
- [How to structure your Git Commits](#how-to-structure-your-git-commits)
- [Contributing new ecosystems](#contributing-new-ecosystems)

## Contribution workflow

1. Fork the project.
2. Get the [development environment running](README.md#getting-a-development-environment-running).
3. Make your feature addition or bug fix.
4. Add [tests for it](README.md#running-tests). This is important so we don't break it in a future version unintentionally.
5. Send a pull request. The tests will run on it automatically, so don't worry if you couldn't get them running locally.

## Project layout

There's a good description of the project's layout in our [README's Architecture section](README.md#architecture-and-code-layout), but if you're
struggling to understand how anything works please don't hesitate to create an issue.

## How to structure your Git Commits

1. Commit messages matter. [Here's how to write them well](https://cbea.ms/git-commit/).
2. We ask for one-commit-per-logical change. This generally results in one-commit-per-PR, but it's okay if a PR contains
   multiple commits when it's easier to understand each commit as a distinct unit of work, but they must all be landed together.
   A general rule of thumb is "What will make this code change simplest to understand for someone `git blame` spelunking down the road?"
3. Because of ☝️ we will generally merge-via-squash. However, if a PR contains multiple commits that shouldn't be squashed, then we will typically merge via a merge commit and not a rebase since merge-via-rebase can break `git bisect`.

## Contributing new ecosystems

We are not currently accepting new ecosystems into `dependabot-core`, starting in December 2020.

### Why have we paused accepting new ecosystems?

Dependabot has grown dramatically in the last few years since integrating with GitHub. We are now [used by millions of repositories](https://octoverse.github.com/#securing-software) across [16 package managers](https://docs.github.com/en/free-pro-team@latest/github/administering-a-repository/about-dependabot-version-updates#supported-repositories-and-ecosystems). We aim to provide the best user experience
possible for each of these, but we have found we've lacked the capacity – and in some cases the in-house expertise – to support new ecosystems in the last year. We want to be
confident we can support each ecosystem we merge.

In the immediate future, we want to focus more of our resources on merging improvements to the ecosystems we already support. This does not mean that we are stopping work or investing less in this space - in fact, we're investing more, to make it a great user experience. This tough call means we can also provide a better experience for our contributors, where PRs don't go stale while waiting for a review.

If you are an ecosystem maintainer and are interested in integrating with Dependabot, and are willing to help provide the expertise necessary to build and support it, please open an issue and let us know.

We hope to be able to accept community contributions for ecosystem support again soon.

### What's next?

In `dependabot-core`, each ecosystem implementation is in its own gem so you can use Dependabot for a language
we have not merged by creating a [script](https://github.com/dependabot/dependabot-script) to run your own gem or
fork of core, e.g. [dependabot-lein-runner](https://github.com/CGA1123/dependabot-lein-runner)

Our plan in the year ahead is to invest more developer time directly in `dependabot-core` to improve our architecture so
each ecosystem is more isolated and testable. We also want to make a consistency pass on existing ecosystems so that there
is a clearer interface between core and the language-specific tooling.

Our goal is make it easier to create and test Dependabot extensions so there is a paved path for running additional
ecosystems in the future.
