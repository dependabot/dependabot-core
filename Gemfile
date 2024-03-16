# frozen_string_literal: true

source "https://rubygems.org"

gem "dependabot-bundler", path: "bundler"
gem "dependabot-cargo", path: "cargo"
gem "dependabot-common", path: "common"
gem "dependabot-composer", path: "composer"
gem "dependabot-devcontainers", path: "devcontainers"
gem "dependabot-docker", path: "docker"
gem "dependabot-elm", path: "elm"
gem "dependabot-github_actions", path: "github_actions"
gem "dependabot-git_submodules", path: "git_submodules"
gem "dependabot-go_modules", path: "go_modules"
gem "dependabot-gradle", path: "gradle"
gem "dependabot-hex", path: "hex"
gem "dependabot-maven", path: "maven"
gem "dependabot-npm_and_yarn", path: "npm_and_yarn"
gem "dependabot-nuget", path: "nuget"
gem "dependabot-pub", path: "pub"
gem "dependabot-python", path: "python"
gem "dependabot-silent", path: "silent"
gem "dependabot-swift", path: "swift"
gem "dependabot-terraform", path: "terraform"

# Sorbet
gem "sorbet", "0.5.11288", group: :development
gem "tapioca", "0.12.0", require: false, group: :development

common_gemspec = File.expand_path("common/dependabot-common.gemspec", __dir__)

deps_shared_with_common = %w(
  debug
  gpgme
  rake
  rspec-its
  rspec-sorbet
  rubocop
  rubocop-performance
  rubocop-rspec
  rubocop-sorbet
  stackprof
  turbo_tests
  vcr
  webmock
  webrick
)

Dir.chdir(File.dirname(common_gemspec)) do
  Gem::Specification.load(common_gemspec).development_dependencies.each do |dep|
    next unless deps_shared_with_common.include?(dep.name)

    gem dep.name, *dep.requirement.as_list
  end
end
