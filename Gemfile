# frozen_string_literal: true

source "https://rubygems.org"

gemspec path: "bundler"
gemspec path: "cargo"
gemspec path: "common"
gemspec path: "composer"
gemspec path: "docker"
gemspec path: "elm"
gemspec path: "github_actions"
gemspec path: "git_submodules"
gemspec path: "go_modules"
gemspec path: "gradle"
gemspec path: "hex"
gemspec path: "maven"
gemspec path: "npm_and_yarn"
gemspec path: "nuget"
gemspec path: "pub"
gemspec path: "python"
gemspec path: "swift"
gemspec path: "terraform"

# Visual Studio Code integration
gem "reek", group: :development
gem "solargraph", group: :development

# Sorbet
gem "sorbet", "0.5.11156", group: :development
gem "tapioca", "0.11.14", require: false, group: :development

common_gemspec = File.expand_path("common/dependabot-common.gemspec", __dir__)

deps_shared_with_common = %w(
  gpgme
  rake
  stackprof
  webmock
  webrick
)

Dir.chdir(File.dirname(common_gemspec)) do
  Gem::Specification.load(common_gemspec).development_dependencies.each do |dep|
    next unless deps_shared_with_common.include?(dep.name)

    gem dep.name, *dep.requirement.as_list
  end
end
