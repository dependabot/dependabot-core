# frozen_string_literal: true
Gem::Specification.new do |spec|
  spec.name         = "example"
  spec.version      = "0.9.3"
  spec.summary      = "Automated dependency management"
  spec.description  = "Core logic for updating a GitHub repos dependencies"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/example"
  spec.license      = "MIT"

  spec.require_path = "lib"
  spec.files        = Dir["CHANGELOG.md", "LICENSE.txt", "README.md",
                          "lib/**/*", "helpers/**/*"]

  spec.required_ruby_version = ">= 2.4.0"
  spec.required_rubygems_version = ">= 2.6.11"

  spec.add_dependency 'business', '~> 1.0'
end
