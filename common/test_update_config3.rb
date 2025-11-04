require_relative 'lib/dependabot/config/update_config'
require 'dependabot/dependency'

# Register bundler requirement class (it should already be registered in real usage)
require 'dependabot/bundler/requirement'
Dependabot::Utils.register_requirement_class("bundler", Dependabot::Bundler::Requirement)

# Test with a normal bundler dependency
dep = Dependabot::Dependency.new(
  name: "rails",
  requirements: [{
    requirement: "~> 7.0",
    file: "Gemfile",
    groups: ["default"],
    source: nil
  }],
  version: "7.0.8",
  package_manager: "bundler"
)

# Ignore that should overlap (blocks versions >= 7.1.0)
ignore_cond = Dependabot::Config::IgnoreCondition.new(
  dependency_name: "rails",
  versions: [">= 7.1.0"]
)

config = Dependabot::Config::UpdateConfig.new(ignore_conditions: [ignore_cond])
result = config.ignored_versions_for(dep)

puts "Ignored versions for rails ~> 7.0 with ignore >= 7.1.0: #{result.inspect}"
puts "Expected: ['>= 7.1.0'] (should keep the ignore as it overlaps with ~> 7.0)"
