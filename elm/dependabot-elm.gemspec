# frozen_string_literal: true

require "find"

Gem::Specification.new do |spec|
  core_gemspec = Bundler.load_gemspec_uncached("../dependabot-core.gemspec")

  spec.name         = "dependabot-elm"
  spec.summary      = "Elm support for dependabot-core"
  spec.version      = core_gemspec.version
  spec.description  = core_gemspec.description

  spec.author       = core_gemspec.author
  spec.email        = core_gemspec.email
  spec.homepage     = core_gemspec.homepage
  spec.license      = core_gemspec.license

  spec.require_path = "lib"
  spec.files        = Dir["lib/**/*"]

  spec.required_ruby_version = core_gemspec.required_ruby_version
  spec.required_rubygems_version = core_gemspec.required_ruby_version

  spec.add_dependency "dependabot-core", Dependabot::VERSION

  core_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, dep.requirement.to_s
  end
end
