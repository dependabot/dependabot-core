# frozen_string_literal: true

require "dependabot/dependency_group"

# This class implements our strategy for keeping track of and matching dependency
# groups that are defined by users in their dependabot config file.
#
# We instantiate the DependencyGroupEngine after parsing dependencies, configuring
# any groups from the job's configuration before assigning the dependency list to
# the groups.
#
# We permit dependencies to be in more than one group and also track those which
# have zero matches so they may be updated individuall.
#
# **Note:** This is currently an experimental feature which is not supported
#           in the service or as an integration point.
#
module Dependabot
  class DependencyGroupEngine
    class ConfigurationError < StandardError; end

    def self.from_job_config(job:)
      groups = job.dependency_groups.map do |group|
        Dependabot::DependencyGroup.new(name: group["name"], rules: group["rules"])
      end

      new(dependency_groups: groups)
    end

    attr_reader :dependency_groups, :groups_calculated, :ungrouped_dependencies

    def find_group(name:)
      dependency_groups.find { |group| group.name == name }
    end

    def assign_to_groups!(dependencies:)
      raise ConfigurationError, "dependency groups have already been configured!" if @groups_calculated

      if dependency_groups.any?
        dependencies.each do |dependency|
          groups = groups_for(dependency)

          @ungrouped_dependencies << dependency if groups.empty?

          groups.each do |group|
            group.dependencies.push(dependency)
          end
        end
      else
        @ungrouped_dependencies = dependencies
      end

      @groups_calculated = true
    end

    private

    def initialize(dependency_groups:)
      @dependency_groups = dependency_groups
      @ungrouped_dependencies = []
      @groups_calculated = false
    end

    def groups_for(dependency)
      return [] if dependency.nil?
      return [] unless dependency.instance_of?(Dependabot::Dependency)

      @dependency_groups.select do |group|
        group.contains?(dependency)
      end
    end
  end
end
