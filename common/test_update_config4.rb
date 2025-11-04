require_relative 'lib/dependabot/config/update_config'
require 'dependabot/dependency'
require 'dependabot/bundler/requirement'
Dependabot::Utils.register_requirement_class("bundler", Dependabot::Bundler::Requirement)

# Test pandas scenario from the issue
dep = Dependabot::Dependency.new(
  name: "test-gem",
  requirements: [{
    requirement: "< 2.0",
    file: "Gemfile",
    groups: ["test"],
    source: nil
  }],
  version: "1.5.0",
  package_manager: "bundler"
)

# Ignore that should NOT overlap (blocks versions >= 2.0)
ignore_cond = Dependabot::Config::IgnoreCondition.new(
  dependency_name: "test-gem",
  versions: [">= 2.0"]
)

config = Dependabot::Config::UpdateConfig.new(ignore_conditions: [ignore_cond])
result = config.ignored_versions_for(dep)

puts "Ignored versions for test-gem < 2.0 with ignore >= 2.0: #{result.inspect}"
puts "Expected: [] (should filter out the ignore as it doesn't overlap with < 2.0)"
