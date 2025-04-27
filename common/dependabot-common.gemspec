# frozen_string_literal: true

require "./lib/dependabot"

Gem::Specification.new do |spec|
  spec.name         = "dependabot-common"
  spec.summary      = "Shared code used across Dependabot Core"
  spec.description  = "Dependabot-Common provides the shared code used across Dependabot. " \
                      "If you want support for multiple package managers, you probably want the meta-gem " \
                      "dependabot-omnibus."

  spec.author       = "Dependabot"
  spec.email        = "opensource@github.com"
  spec.homepage     = "https://github.com/dependabot/dependabot-core"
  spec.license      = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/dependabot/dependabot-core/issues",
    "changelog_uri" => "https://github.com/dependabot/dependabot-core/releases/tag/v#{Dependabot::VERSION}"
  }

  spec.version = Dependabot::VERSION
  spec.required_ruby_version = ">= 3.1.0"
  spec.required_rubygems_version = ">= 3.3.7"

  spec.require_path = "lib"
  spec.files        = []

  spec.add_dependency "aws-sdk-codecommit", "~> 1.28"
  spec.add_dependency "aws-sdk-ecr", "~> 1.5"
  spec.add_dependency "bundler", ">= 1.16", "< 3.0.0"
  spec.add_dependency "commonmarker", ">= 0.20.1", "< 0.24.0"
  spec.add_dependency "docker_registry2", "~> 1.18.2"
  spec.add_dependency "excon", "~> 0.109"
  spec.add_dependency "faraday", "2.7.11"
  spec.add_dependency "faraday-retry", "2.2.0"
  spec.add_dependency "gitlab", "5.0.0"
  spec.add_dependency "json", "< 2.7"
  spec.add_dependency "nokogiri", "~> 1.8"
  spec.add_dependency "octokit", ">= 4.6", "< 8.0"
  spec.add_dependency "opentelemetry-api", "~> 1.5"
  spec.add_dependency "opentelemetry-logs-api", "~> 0.2"
  spec.add_dependency "opentelemetry-metrics-api", "~> 0.3"
  spec.add_dependency "parser", ">= 2.5", "< 4.0"
  spec.add_dependency "psych", "~> 5.0"
  spec.add_dependency "sorbet-runtime", "~> 0.5.11952"
  spec.add_dependency "stackprof", "~> 0.2.16"
  spec.add_dependency "toml-rb", ">= 1.1.2"

  spec.add_development_dependency "debug", "~> 1.9.2"
  spec.add_development_dependency "gpgme", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-its", "~> 1.3"
  spec.add_development_dependency "rspec-sorbet", "~> 1.9.2"
  spec.add_development_dependency "rubocop", "~> 1.67.0"
  spec.add_development_dependency "rubocop-performance", "~> 1.22.1"
  spec.add_development_dependency "rubocop-rspec", "~> 2.29.1"
  spec.add_development_dependency "rubocop-sorbet", "~> 0.8.7"
  spec.add_development_dependency "simplecov", "~> 0.22.0"
  spec.add_development_dependency "turbo_tests", "~> 2.2.0"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "webrick", ">= 1.7"

  next unless File.exist?("../.gitignore")

  spec.files += `git -C #{__dir__} ls-files lib bin -z`.split("\x0")
end
