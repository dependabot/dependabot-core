require_relative 'lib/dependabot/config/update_config'
require 'dependabot/dependency'
require 'dependabot/bundler/requirement'
Dependabot::Utils.register_requirement_class("bundler", Dependabot::Bundler::Requirement)

# Test with invalid requirement that might throw
dep = Dependabot::Dependency.new(
  name: "test-gem",
  requirements: [{
    requirement: "invalid_req",
    file: "Gemfile",
    groups: ["default"],
    source: nil
  }],
  version: "1.0.0",
  package_manager: "bundler"
)

ignore_cond = Dependabot::Config::IgnoreCondition.new(
  dependency_name: "test-gem",
  versions: [">= 1.5.0"]
)

config = Dependabot::Config::UpdateConfig.new(ignore_conditions: [ignore_cond])
begin
  result = config.ignored_versions_for(dep)
  puts "Ignored versions with invalid requirement: #{result.inspect}"
  puts "Expected: ['>= 1.5.0'] (should keep ignores when req can't be parsed)"
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end
