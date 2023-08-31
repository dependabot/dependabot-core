# frozen_string_literal: true

# This is a placeholder gem to prevent namesquatting on https://rubygems.org/gems/dependabot-core
# Any updates must be manually published to RubyGems.
# It's excluded from the normal release process because it's not expected to change.

Gem::Specification.new do |spec|
  spec.name = "dependabot-core"
  spec.summary      = "This is a placeholder gem to prevent namesquatting. " \
                      "You probably want the gem 'dependabot-omnibus'."
  spec.description  = "This is a placeholder gem to prevent namesquatting. " \
                      "You probably want the gem 'dependabot-omnibus'."
  spec.authors     = "Dependabot"
  spec.email       = "opensource@github.com"
  spec.files       = [] # intentionally empty, this is a placeholder gem to prevent namesquatting
  spec.homepage    = "https://github.com/dependabot/dependabot-core"
  spec.license = "Nonstandard" # License Zero Prosperity Public License

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/dependabot/dependabot-core/issues"
  }

  spec.version = "0.95.1"
  # Since a placeholder gem, no need to keep `required_ruby_version` up to date with `.ruby-version`
  spec.required_ruby_version = ">= 3" # rubocop:disable Gemspec/RequiredRubyVersion
end
