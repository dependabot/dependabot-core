# Feedback and contributions to Dependabot

👋 Want to give us feedback on Dependabot, or contribute to it? That's great - thank you so much!

#### Overview

- [Contribution workflow](#contribution-workflow)
- [Setup instructions](#setup-instructions)
- [Project layout](#project-layout)
- [Contributing new ecosystems](#contributing-new-ecosystems)

## Contribution workflow

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so we don't break it in a future version unintentionally.
 * Send a pull request. The tests will run on it automatically, so don't worry if you couldn't get them running locally.

## Setup instructions

Dependabot runs through [Docker](https://www.docker.com/products/docker-desktop/), so that's the only thing you need to get started.

Then, assuming you're working on a single language, you'll need to start a
development container for that language through

```
bin/docker-dev-shell <ecosystem>
```

The name of the ecosystem should be one of the top level root folders in this
repo. That folder is where you'll want to make your changes.

Once inside the development container, switch to the ecosystem folder you want
to work with and from there you can run tests with

```
rspec
```

You can also run the specific tests for the file you're working on with, for
example:

```
rspec spec/dependabot/file_updaters/elixir
```

## Project layout

There's a good description of the project's layout in our [README](README.md), but if you're struggling to understand how anything works please don't hesitate to create an issue.

## Contributing new ecosystems

We are not currently accepting new ecosystems into `dependabot-core`, starting in December 2020.

### Why have we paused accepting new ecosystems?

Dependabot has grown dramatically in the last two years since integrating with GitHub. We are now [used by millions of repositories](https://octoverse.github.com/#securing-software) across [16 package managers](https://docs.github.com/en/free-pro-team@latest/github/administering-a-repository/about-dependabot-version-updates#supported-repositories-and-ecosystems). We aim to provide the best user experience
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

