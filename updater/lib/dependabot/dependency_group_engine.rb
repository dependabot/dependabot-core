# frozen_string_literal: true

require "dependabot/dependency_group"

# This class implements our strategy for keeping track of and matching dependency
# groups that are defined by users in their dependabot config file.
#
# This is a static class tied to the lifecycle of a Job
# - Each UpdateJob registers its own DependencyGroupEngine which calculates
#    the grouped and ungrouped dependencies for a DependencySnapshot
# - Groups are only calculated once after the Job has registered its dependencies
# - All allowed dependencies should be passed in to the calculate_dependency_groups! method
#
# **Note:** This is currently an experimental feature which is not supported
#           in the service or as an integration point.
#
module Dependabot
  module DependencyGroupEngine
    @groups_calculated = false
    @registered_groups = []

    @dependency_groups = {}
    @ungrouped_dependencies = []

    def self.reset!
      @groups_calculated = false
      @registered_groups = []

      @dependency_groups = {}
      @ungrouped_dependencies = []
    end

    # Eventually the key for a dependency group should be a hash since names _can_ conflict within jobs
    def self.register(name, rules)
      @registered_groups.push Dependabot::DependencyGroup.new(name: name, rules: rules)
    end

    def self.groups_for(dependency)
      return [] if dependency.nil?
      return [] unless dependency.instance_of?(Dependabot::Dependency)

      @registered_groups.select do |group|
        group.contains?(dependency)
      end
    end

    # { group_name => [DependencyGroup], ... }
    def self.dependency_groups(dependencies)
      return @dependency_groups if @groups_calculated

      @groups_calculated = calculate_dependency_groups!(dependencies)

      @dependency_groups
    end

    # Returns a list of dependencies that do not belong to any of the groups
    def self.ungrouped_dependencies(dependencies)
      return @ungrouped_dependencies if @groups_calculated

      @groups_calculated = calculate_dependency_groups!(dependencies)

      @ungrouped_dependencies
    end

    def self.calculate_dependency_groups!(dependencies)
      # If we try to calculate dependency groups when there are no groups registered
      # then all of the dependencies end up in the ungrouped list which can break
      # an UpdateAllVersions#dependencies check
      return false unless @registered_groups.any?

      dependencies.each do |dependency|
        groups = groups_for(dependency)

        @ungrouped_dependencies << dependency if groups.empty?

        groups.each do |group|
          group.dependencies.push(dependency)
          @dependency_groups[group.name.to_sym] = group
        end
      end

      true
    end
  end
end
