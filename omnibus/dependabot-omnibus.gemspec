# frozen_string_literal: true

require "find"

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

  spec.add_dependency "dependabot-core", Dependabot::VERSION
  spec.add_dependency "dependabot-docker", Dependabot::VERSION
  spec.add_dependency "dependabot-git-submodules", Dependabot::VERSION
  spec.add_dependency "dependabot-terraform", Dependabot::VERSION
end
