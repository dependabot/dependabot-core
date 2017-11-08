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
  spec.required_rubygems_version = ">= 2.6.13"

  spec.add_dependency "bundler", "~> 1.16"
  spec.add_dependency "docker_registry2", "~> 1.2"
  spec.add_dependency "excon", "~> 0.55"
  spec.add_dependency "gitlab", "~> 4.1"
  spec.add_dependency "octokit", "~> 4.6"
  spec.add_dependency "parseconfig", "~> 1.0.8"
  spec.add_dependency "parser", "~> 2.4.0"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.7.0"
  spec.add_development_dependency "rspec-its", "~> 1.2.0"
  spec.add_development_dependency "rubocop", "~> 0.51.0"
  spec.add_development_dependency "webmock", "~> 3.1.0"
end
