# typed: true
# frozen_string_literal: true

require_relative "version"
require_relative "requirement"

require_relative "file_fetcher"
require_relative "file_parser"
require_relative "update_checker"
require_relative "file_updater"

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "dummy",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("runtime")
    return true if groups.include?("default")

    groups.any? { |g| g.include?("prod") }
  end
)
