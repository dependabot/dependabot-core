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
        Dependabot::DependencyGroup.new(name: group["name"], rules: group["rules"], applies_to: group["applies-to"])
      end

      # Filter out version updates when doing security updates and visa versa
      groups = if job.security_updates_only?
                 groups.select { |group| group.applies_to == "security-updates" }
               else
                 groups.select { |group| group.applies_to == "version-updates" }
               end

      new(dependency_groups: groups)
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
        specificity_calculator = Dependabot::Updater::PatternSpecificityCalculator.new

        dependencies.each do |dependency|
          matched_groups = @dependency_groups.each_with_object([]) do |group, matches|
            next unless group.contains?(dependency)
            next if should_skip_due_to_specificity?(group, dependency, specificity_calculator)

            group.dependencies.push(dependency)
            matches << group
          end

          # If we had no matches, collect the dependency as ungrouped
          @ungrouped_dependencies << dependency if matched_groups.empty?
        end
      else
        @ungrouped_dependencies += dependencies
      end

      validate_groups
    end

    private

    sig { params(dependency_groups: T::Array[Dependabot::DependencyGroup]).void }
    def initialize(dependency_groups:)
      @dependency_groups = dependency_groups
      @ungrouped_dependencies = T.let([], T::Array[Dependabot::Dependency])
    end

    sig { void }
    def validate_groups
      empty_groups = dependency_groups.select { |group| group.dependencies.empty? }
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
      specificity_calculator.dependency_belongs_to_more_specific_group?(
        group, dependency, @dependency_groups, contains_checker, dependency.directory
      )
    end
  end
end
