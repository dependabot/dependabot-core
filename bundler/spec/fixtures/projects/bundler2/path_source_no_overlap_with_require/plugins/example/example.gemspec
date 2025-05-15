# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'example/version'

Gem::Specification.new do |spec|
  spec.name         = "example"
  spec.version      = Example::VERSION
  spec.summary      = "Automated dependency management #{Example::VERSION}"
  spec.description  = "Core logic for updating a GitHub repos dependencies"
  spec.date         = Example::DATE

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/example"
  spec.license      = "MIT"

  spec.require_path = "lib"
  spec.files        = Dir["CHANGELOG.md", "LICENSE.txt", "README.md",
                          "lib/**/*", "helpers/**/*"]

  spec.required_ruby_version = ">= 2.4.0"
  spec.required_rubygems_version = ">= 2.6.11"

  spec.add_dependency 'json', '~> 1.0'
end
