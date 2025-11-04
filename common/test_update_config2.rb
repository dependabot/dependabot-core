require_relative 'lib/dependabot/config/update_config'
require 'dependabot/dependency'

# Test with a dependency that has requirements with unknown package manager
dep = Dependabot::Dependency.new(
  name: "test-pkg",
  requirements: [{
    requirement: ">= 1.0",
    file: "test.txt",
    groups: ["default"],
    source: nil
  }],
  version: "1.0.0",
  package_manager: "unknown_pm"
)

ignore_cond = Dependabot::Config::IgnoreCondition.new(
  dependency_name: "test-pkg",
  versions: [">= 1.5.0"]
)

config = Dependabot::Config::UpdateConfig.new(ignore_conditions: [ignore_cond])
result = config.ignored_versions_for(dep)

puts "Ignored versions for dependency with unknown package manager: #{result.inspect}"
puts "Expected: ['>= 1.5.0'] (should keep all ignores when package manager not registered)"
