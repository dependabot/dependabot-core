# Feedback and contributions to Dependabot

👋 Want to give us feedback on Dependabot, or contribute to it? That's great - thank you so much!

#### Overview

* [Feedback workflow](#feedback-workflow)
* [Contribution workflow](#contribution-workflow)
* [Setup instructions](#setup-instructions)
* [Project layout](#project-layout)

## Feedback workflow

 * Go right ahead and [create an issue](https://github.com/dependabot/dependabot-core/issues), whatever it is. There are no stupid questions, no required formats, and we're always happy to help, whatever it is!
 * If you'd rather talk to us in private you can email us on [support@dependabot.com](mailto:support@dependabot.com).

## Contribution workflow

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so we don't break it in a future version unintentionally.
 * Send a pull request. The tests will run on it automatically, so don't worry if you couldn't get them running locally.

## Setup instructions

Getting set up to run all of the tests on Dependabot isn't as simple as we'd like it to be - sorry about that. Dependabot needs to shell out to multiple different languages to correctly update dependency files, which makes things a little complicated.

Assuming you're working on a single language, the best thing to do is just to install Ruby and the language you're working on as follows:

* [Install rbenv](https://github.com/rbenv/rbenv#installation) (a Ruby version manager)
* [Install the latest Ruby](https://github.com/rbenv/rbenv#installing-ruby-versions)
* Install Bundler with `gem install bundler` (this is Ruby's package manager)
* Install Dependabot's Ruby dependencies with `bundle install`
* Install the language dependencies for whatever languages you're working on (see [how we do it in CI](.circleci/config.yml))
* Run the tests for the file you're working on with `bundle exec rspec spec/dependabot/file_updaters/elixir/` (for example). They should be green (although might need an internet connection).

## Project layout

There's a good description of the project's layout in our [README](README.md), but if you're struggling to understand how anything works please don't hesitate to create an issue.
