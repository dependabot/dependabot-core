# frozen_string_literal: true

require "find"

# rubocop:disable Metrics/BlockLength
Gem::Specification.new do |spec|
  core_gemspec = Bundler.load_gemspec_uncached("../dependabot-core.gemspec")

  spec.name         = "dependabot-omnibus"
  spec.summary      = "Meta-package that depends on all core dependabot-core " \
                      "package managers"
  spec.version      = core_gemspec.version
  spec.description  = core_gemspec.description

  spec.author       = core_gemspec.author
  spec.email        = core_gemspec.email
  spec.homepage     = core_gemspec.homepage
  spec.license      = core_gemspec.license

  spec.require_path = "lib"
  spec.files        = ["lib/dependabot/omnibus.rb"]

  spec.add_dependency "dependabot-cargo", Dependabot::VERSION
  spec.add_dependency "dependabot-composer", Dependabot::VERSION
  spec.add_dependency "dependabot-core", Dependabot::VERSION
  spec.add_dependency "dependabot-dep", Dependabot::VERSION
  spec.add_dependency "dependabot-docker", Dependabot::VERSION
  spec.add_dependency "dependabot-elm", Dependabot::VERSION
  spec.add_dependency "dependabot-git_submodules", Dependabot::VERSION
  spec.add_dependency "dependabot-go_modules", Dependabot::VERSION
  spec.add_dependency "dependabot-gradle", Dependabot::VERSION
  spec.add_dependency "dependabot-hex", Dependabot::VERSION
  spec.add_dependency "dependabot-maven", Dependabot::VERSION
  spec.add_dependency "dependabot-nuget", Dependabot::VERSION
  spec.add_dependency "dependabot-python", Dependabot::VERSION
  spec.add_dependency "dependabot-terraform", Dependabot::VERSION
end
# rubocop:disable Metrics/BlockLength
