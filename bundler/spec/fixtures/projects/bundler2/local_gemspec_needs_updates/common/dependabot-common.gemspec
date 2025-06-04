# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name         = "dependabot-common"
  spec.summary      = "Shared code used across Dependabot Core"
  spec.description  = "Dependabot-Common provides the shared code used across Dependabot. " \
                      "If you want support for multiple package managers, you probably want the meta-gem " \
                      "dependabot-omnibus."

  spec.author       = "Dependabot"
  spec.email        = "opensource@github.com"
  spec.homepage     = "https://github.com/dependabot/dependabot-core"
  spec.license      = "Nonstandard" # License Zero Prosperity Public License

  spec.version = "0.218.0"
  spec.required_ruby_version = ">= 3.1.0"
  spec.required_rubygems_version = ">= 3.3.7"

  spec.add_dependency "docker_registry2", "~> 1.14.0"
end
