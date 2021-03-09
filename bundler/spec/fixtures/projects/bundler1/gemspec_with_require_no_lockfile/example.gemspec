# frozen_string_literal: true

require "find"

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "example/version"

Gem::Specification.new do |spec|
  spec.name         = "example"
  spec.version      = Example::VERSION
  spec.summary      = "Automated dependency management #{Example::VERSION}"
  spec.description  = "Core logic for updating a GitHub repos dependencies"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/example"
  spec.license      = "MIT"

  spec.require_path = "lib"
  spec.files        = Dir["CHANGELOG.md", "LICENSE.txt", "README.md",
                          "lib/**/*", "helpers/**/*"]
  Find.find("lib", "helpers") do |path|
    if ignores.any? { |i| File.fnmatch(i, "/" + path, File::FNM_DOTMATCH) }
      Find.prune
    else
      spec.files << path unless File.directory?(path)
    end
  end

  spec.required_ruby_version = ">= 2.4.0"
  spec.required_rubygems_version = ">= 2.6.11"

  spec.add_dependency "bundler", ">= 1.12.0"
  spec.add_dependency "excon", "~> 0.55"
  spec.add_dependency "gemnasium-parser", "~> 0.1"
  spec.add_dependency "gems", "~> 1.0"
  spec.add_dependency "gitlab", "~> 4.1"
  spec.add_dependency "octokit", "~> 4.6"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.5.0"
  spec.add_development_dependency "rspec-its", "~> 1.2.0"
  spec.add_development_dependency "rubocop", "~> 0.48.0"
  spec.add_development_dependency "webmock", "~> 2.3.1"
end
