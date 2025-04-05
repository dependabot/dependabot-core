# frozen_string_literal: true

Gem::Specification.new do |spec|
  common_gemspec =
    Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

  spec.name         = "dependabot-nuget"
  spec.summary      = "Provides Dependabot support for .NET (NuGet)"
  spec.description  = "Dependabot-Nuget provides support for bumping .NET (NuGet) packages via Dependabot. " \
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
  spec.files        = []

  spec.add_dependency "dependabot-common", Dependabot::VERSION
  spec.add_dependency "rubyzip", ">= 2.3.2", "< 3.0"

  common_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, *dep.requirement.as_list
  end

  next unless File.exist?("../.gitignore")

  spec.files += `git -C #{__dir__} ls-files lib helpers -z`.split("\x0")
end
