# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_group"
require "dependabot/updater/pattern_specificity_calculator"

# This class implements our strategy for keeping track of and matching dependency
# groups that are defined by users in their dependabot config file.
#
# We instantiate the DependencyGroupEngine after parsing dependencies, configuring
# any groups from the job's configuration before assigning the dependency list to
# the groups.
#
# We permit dependencies to be in more than one group and also track those which
# have zero matches so they may be updated individually.
#
# **Note:** This is currently an experimental feature which is not supported
#           in the service or as an integration point.
#
module Dependabot
  class DependencyGroupEngine
    extend T::Sig

    class ConfigurationError < StandardError; end

    PACKAGE_MANAGERS_SUPPORTING_DEPENDENCY_TYPE = T.let(
      %w(bundler composer hex maven npm_and_yarn pip uv silent).freeze,
      T::Array[String]
    )

    sig { params(job: Dependabot::Job).returns(Dependabot::DependencyGroupEngine) }
    def self.from_job_config(job:)
      validate_group_configuration!(job)

      groups = job.dependency_groups.map do |group|
        Dependabot::DependencyGroup.new(
          name: group["name"],
          rules: group["rules"],
          applies_to: group["applies-to"],
          group_by: group.dig("rules", "group-by")
        )
      end

      # Filter out version updates when doing security updates and visa versa
      filtered_groups = if job.security_updates_only?
                          groups.select { |group| group.applies_to == "security-updates" }
                        else
                          groups.select { |group| group.applies_to == "version-updates" }
                        end

      if filtered_groups.count != groups.count
        filtered_count = groups.count - filtered_groups.count
        update_type = job.security_updates_only? ? "security" : "version"
        Dependabot.logger.info(
          "Filtered #{filtered_count} group(s) not applicable to #{update_type} updates"
        )
      end

      new(dependency_groups: filtered_groups)
    end

    sig { params(job: Dependabot::Job).void }
    def self.validate_group_configuration!(job)
      return unless job.dependency_groups.any?

      unsupported_groups = job.dependency_groups.select do |group|
        rules = group["rules"] || {}
        rules.key?("dependency-type") &&
          !PACKAGE_MANAGERS_SUPPORTING_DEPENDENCY_TYPE.include?(job.package_manager)
      end

      return unless unsupported_groups.any?

      group_names = unsupported_groups.map { |g| g["name"] }.join(", ")
      Dependabot.logger.warn <<~WARN
        The 'dependency-type' option is not supported for the '#{job.package_manager}' package manager.
        It is only supported for: #{PACKAGE_MANAGERS_SUPPORTING_DEPENDENCY_TYPE.join(', ')}.
        Affected groups: #{group_names}

        This option will be ignored. Please remove it from your configuration or use a supported package manager.
      WARN
    end

    sig { returns(T::Array[Dependabot::DependencyGroup]) }
    attr_reader :dependency_groups

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :ungrouped_dependencies

    sig { params(name: String).returns(T.nilable(Dependabot::DependencyGroup)) }
    def find_group(name:)
      dependency_groups.find { |group| group.name == name }
    end

    sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
    def assign_to_groups!(dependencies:)
      if dependency_groups.any?
        assign_dependencies_to_groups(dependencies)
        create_dynamic_subgroups_for_dependency_name_groups(dependencies)
      else
        @ungrouped_dependencies += dependencies
      end

      validate_groups
    end

    private

    sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
    def assign_dependencies_to_groups(dependencies)
      specificity_calculator = Dependabot::Updater::PatternSpecificityCalculator.new

      dependencies.each do |dependency|
        matched_groups = assign_dependency_to_matching_groups(dependency, specificity_calculator)
        mark_ungrouped_if_no_matches(dependency, matched_groups)
      end
    end

    sig do
      params(
        dependency: Dependabot::Dependency,
        specificity_calculator: Dependabot::Updater::PatternSpecificityCalculator
      ).returns(T::Array[Dependabot::DependencyGroup])
    end
    def assign_dependency_to_matching_groups(dependency, specificity_calculator)
      @dependency_groups.each_with_object([]) do |group, matches|
        next if group.group_by_dependency_name?
        next unless group.contains?(dependency)
        next if should_skip_due_to_specificity?(group, dependency, specificity_calculator)

        group.dependencies.push(dependency)
        matches << group
      end
    end

    sig { params(dependency: Dependabot::Dependency, matched_groups: T::Array[Dependabot::DependencyGroup]).void }
    def mark_ungrouped_if_no_matches(dependency, matched_groups)
      return unless matched_groups.empty?
      return if matches_group_by_parent_group?(dependency)

      @ungrouped_dependencies << dependency
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def matches_group_by_parent_group?(dependency)
      @dependency_groups.any? do |group|
        group.group_by_dependency_name? && group.contains?(dependency)
      end
    end

    sig { params(dependency_groups: T::Array[Dependabot::DependencyGroup]).void }
    def initialize(dependency_groups:)
      @dependency_groups = dependency_groups
      @ungrouped_dependencies = T.let([], T::Array[Dependabot::Dependency])
    end

    sig { void }
    def validate_groups
      # Exclude parent groups with group_by_dependency_name? from empty group warnings
      # as they intentionally have no direct dependencies (subgroups have them)
      empty_groups = dependency_groups.select do |group|
        group.dependencies.empty? && !group.group_by_dependency_name?
      end
      warn_misconfigured_groups(empty_groups) if empty_groups.any?
    end

    sig { params(groups: T::Array[Dependabot::DependencyGroup]).void }
    def warn_misconfigured_groups(groups)
      Dependabot.logger.warn <<~WARN
        Please check your configuration as there are groups where no dependencies match:
        #{groups.map { |g| "- #{g.name}" }.join("\n")}

        This can happen if:
        - the group's 'pattern' rules are misspelled
        - your configuration's 'allow' rules do not permit any of the dependencies that match the group
        - the dependencies that match the group rules have been removed from your project
      WARN
    end

    sig do
      params(
        group: Dependabot::DependencyGroup,
        dependency: Dependabot::Dependency,
        specificity_calculator: Dependabot::Updater::PatternSpecificityCalculator
      ).returns(T::Boolean)
    end
    def should_skip_due_to_specificity?(group, dependency, specificity_calculator)
      return false unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

      contains_checker = proc { |g, dep, _dir| g.contains?(dep) }
      applies_to = group.applies_to if group.respond_to?(:applies_to)

      Dependabot.logger.info(
        "Checking specificity for #{dependency.name} in group '#{group.name}' (applies_to: #{applies_to || 'nil'})"
      )

      more_specific_group_name = specificity_calculator.find_most_specific_group_name(
        group, dependency, @dependency_groups, contains_checker, dependency.directory, applies_to:
      )

      if more_specific_group_name
        Dependabot.logger.info(
          "Skipping #{dependency.name} for group '#{group.name}' - " \
          "belongs to more specific group '#{more_specific_group_name}'"
        )
        return true
      end

      false
    end

    sig { params(dependencies: T::Array[Dependabot::Dependency]).void }
    def create_dynamic_subgroups_for_dependency_name_groups(dependencies)
      parent_groups = @dependency_groups.select(&:group_by_dependency_name?)

      parent_groups.each do |parent_group|
        matching_deps = dependencies.select { |dep| parent_group.contains?(dep) }

        matching_deps.group_by(&:name).each do |dep_name, deps|
          subgroup = Dependabot::DependencyGroup.new(
            name: "#{parent_group.name}/#{dep_name}",
            rules: parent_group.rules.merge("patterns" => [dep_name]),
            applies_to: parent_group.applies_to
            # NOTE: subgroups don't inherit group_by to prevent infinite recursion
          )
          subgroup.dependencies.concat(deps)
          @dependency_groups << subgroup
        end

        parent_group.dependencies.clear
      end
    end
  end
end
