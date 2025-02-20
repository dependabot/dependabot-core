# frozen_string_literal: true

Gem::Specification.new do |spec|
  common_gemspec =
    Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

  spec.name         = "dependabot-git_submodules"
  spec.summary      = "Provides Dependabot support for Git Submodules"
  spec.description  = "Dependabot-Git_Submodules provides support for bumping git submodules via Dependabot. " \
                      "If you want support for multiple package managers, you probably want the meta-gem " \
                      "dependabot-omnibus."

  spec.author       = common_gemspec.author
  spec.email        = common_gemspec.email
  spec.homepage     = common_gemspec.homepage
  spec.license      = common_gemspec.license

  spec.metadata = {
    "bug_tracker_uri" => common_gemspec.metadata["bug_tracker_uri"],
    "changelog_uri" => common_gemspec.metadata["changelog_uri"]
  }

  spec.version = common_gemspec.version
  spec.required_ruby_version = common_gemspec.required_ruby_version
  spec.required_rubygems_version = common_gemspec.required_ruby_version

  spec.require_path = "lib"
  spec.files        = Dir["lib/**/*"]

  spec.add_dependency "dependabot-common", Dependabot::VERSION
  spec.add_dependency "parseconfig", "~> 1.0", "< 1.2.0"

  common_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, *dep.requirement.as_list
  end
end
