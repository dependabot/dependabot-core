# frozen_string_literal: true
Gem::Specification.new do |spec|
  another_gemspec = Bundler.load_gemspec_uncached("another.gemspec")

  spec.name         = "example"
  spec.version      = "0.9.3"
  spec.summary      = "Automated dependency management"
  spec.description  = "Core logic for updating a GitHub repos dependencies"
  spec.date         = "2019-08-01"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/example"
  spec.license      = "MIT"

  spec.require_path = Dir["lib"]
  spec.files        = Dir["CHANGELOG.md", "LICENSE.txt", "README.md",
                          "lib/**/*", "helpers/**/*"]

  spec.required_ruby_version = ">= 2.4.0"
  spec.required_rubygems_version = ">= 2.6.11"

  spec.add_runtime_dependency "bundler", ">= 1.12.0"
  spec.add_dependency "excon", "~> 0.55"
  spec.add_development_dependency "webmock", "~> 2.3.1"

  another_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, *dep.requirement.as_list
  end
end
