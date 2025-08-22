# typed: false
# frozen_string_literal: true

require_relative "lib/dependabot/local_scanner/version"

Gem::Specification.new do |spec|
  spec.name = "dependabot-local_scanner"
  spec.version = Dependabot::LocalScanner::VERSION
  spec.authors = ["Dependabot"]
  spec.email = ["support@dependabot.com"]
  spec.summary = "Local dependency scanner for Ruby projects"
  spec.description = "A local dependency scanner that allows developers to run Dependabot Core against local Ruby projects without requiring GitHub repository access."
  spec.homepage = "https://github.com/dependabot/dependabot-core"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.glob("lib/**/*") + Dir.glob("bin/**/*") + %w[README.md LICENSE.txt]
  spec.bindir = "bin"
  spec.executables = ["local_ruby_scan"]
  spec.require_paths = ["lib"]

  spec.add_dependency "dependabot-common", Dependabot::LocalScanner::VERSION
  spec.add_dependency "dependabot-bundler", Dependabot::LocalScanner::VERSION

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec-its", "~> 1.3"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rspec", "~> 2.20"
end
