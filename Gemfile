# frozen_string_literal: true

source "https://rubygems.org"

gem "dependabot-bun", path: "bun"
gem "dependabot-bundler", path: "bundler"
gem "dependabot-cargo", path: "cargo"
gem "dependabot-common", path: "common"
gem "dependabot-composer", path: "composer"
gem "dependabot-conda", path: "conda"
gem "dependabot-devcontainers", path: "devcontainers"
gem "dependabot-docker", path: "docker"
gem "dependabot-docker_compose", path: "docker_compose"
gem "dependabot-dotnet_sdk", path: "dotnet_sdk"
gem "dependabot-elm", path: "elm"
gem "dependabot-github_actions", path: "github_actions"
gem "dependabot-git_submodules", path: "git_submodules"
gem "dependabot-go_modules", path: "go_modules"
gem "dependabot-gradle", path: "gradle"
gem "dependabot-helm", path: "helm"
gem "dependabot-hex", path: "hex"
gem "dependabot-maven", path: "maven"
gem "dependabot-npm_and_yarn", path: "npm_and_yarn"
gem "dependabot-nuget", path: "nuget"
gem "dependabot-pub", path: "pub"
gem "dependabot-python", path: "python"
gem "dependabot-rust_toolchain", path: "rust_toolchain"
gem "dependabot-silent", path: "silent"
gem "dependabot-swift", path: "swift"
gem "dependabot-terraform", path: "terraform"
gem "dependabot-uv", path: "uv"
gem "dependabot-vcpkg", path: "vcpkg"

# HTTP client (used by updater module)
gem "http", "~> 5.1"

# Sorbet
gem "sorbet", "0.6.12479", group: :development
gem "tapioca", "0.17.7", require: false, group: :development

gem "zeitwerk", "~> 2.7"

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
  simplecov
  stackprof
  strscan
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
