require_relative 'lib/dependabot/config/update_config'
require 'dependabot/dependency'
require 'dependabot/bundler/requirement'
Dependabot::Utils.register_requirement_class("bundler", Dependabot::Bundler::Requirement)

# Test with complex requirement
dep = Dependabot::Dependency.new(
  name: "test-gem",
  requirements: [{
    requirement: ">= 1.0, < 3.0",
    file: "Gemfile",
    groups: ["default"],
    source: nil
  }],
  version: "2.0.0",
  package_manager: "bundler"
)

# Ignore that overlaps
ignore_cond = Dependabot::Config::IgnoreCondition.new(
  dependency_name: "test-gem",
  versions: [">= 2.5.0"]
)

config = Dependabot::Config::UpdateConfig.new(ignore_conditions: [ignore_cond])
result = config.ignored_versions_for(dep)

puts "Ignored versions for test-gem >= 1.0, < 3.0 with ignore >= 2.5.0: #{result.inspect}"
puts "Expected: ['>= 2.5.0'] (should keep the ignore as 2.5.0-2.9.x overlaps)"
