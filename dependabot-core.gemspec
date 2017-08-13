# frozen_string_literal: true
require "./lib/dependabot/version"

Gem::Specification.new do |spec|
  spec.name         = "dependabot-core"
  spec.version      = Dependabot::VERSION
  spec.summary      = "Automated dependency management"
  spec.description  = "Core logic for updating a GitHub repos dependencies"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/dependabot-core"
  spec.license      = "MIT"

  spec.require_path = "lib"
  spec.files        = Dir["CHANGELOG.md", "LICENSE.txt", "README.md",
                          "lib/**/*", "helpers/**/*"]

  spec.required_ruby_version = ">= 2.4.0"
  spec.required_rubygems_version = ">= 2.6.11"

  spec.add_dependency "bundler", ">= 1.12.0"
  spec.add_dependency "excon", "~> 0.55"
  spec.add_dependency "gemnasium-parser", "~> 0.1"
  spec.add_dependency "gems", "~> 1.0"
  spec.add_dependency "octokit", "~> 4.6"
  spec.add_dependency "gitlab", "~> 4.1"

  spec.add_development_dependency "webmock", ">= 2.3.1", "< 3.1.0"
  spec.add_development_dependency "rspec", "~> 3.5.0"
  spec.add_development_dependency "rspec-its", "~> 1.2.0"
  spec.add_development_dependency "rubocop", ">= 0.48", "< 0.50"
  spec.add_development_dependency "rake"
end
