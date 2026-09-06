# frozen_string_literal: true

Gem::Specification.new do |spec|
  common_gemspec =
    Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

  spec.name         = "dependabot-kotlin_toolchain"
  spec.summary      = "Provides Dependabot support for JetBrains Kotlin Toolchain"
  spec.description  = "dependabot-kotlin_toolchain updates Kotlin Toolchain wrappers, YAML manifests, " \
                      "version catalogs, and explicit built-in technology versions."

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
  spec.add_dependency "dependabot-gradle", Dependabot::VERSION
  spec.add_dependency "dependabot-maven", Dependabot::VERSION
  spec.add_dependency "toml-rb", "~> 4.2"

  common_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, *dep.requirement.as_list
  end
end
