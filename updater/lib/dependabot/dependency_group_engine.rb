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

    sig { params(job: Dependabot::Job).returns(Dependabot::DependencyGroupEngine) }
    def self.from_job_config(job:)
      groups = job.dependency_groups.map do |group|
        Dependabot::DependencyGroup.new(name: group["name"], rules: group["rules"], applies_to: group["applies-to"])
      end

      # Filter out version updates when doing security updates and visa versa
      groups = if job.security_updates_only?
                 groups.select { |group| group.applies_to == "security-updates" }
               else
                 groups.select { |group| group.applies_to == "version-updates" }
               end

      # Validate and filter out invalid groups
      groups = validate_and_filter_groups(groups, job.package_manager)

      new(dependency_groups: groups)
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

    # Class method to validate and filter groups before instantiation
    sig do
      params(
        groups: T::Array[Dependabot::DependencyGroup],
        package_manager: String
      ).returns(T::Array[Dependabot::DependencyGroup])
    end
    def self.validate_and_filter_groups(groups, package_manager)
      # List of known package manager names that should not be used as group names
      # to prevent confusion with automatically generated groups
      reserved_names = T.let(
        %w(
          npm_and_yarn npm yarn bundler pip maven gradle cargo composer
          gomod go_modules terraform hex pub docker nuget mix swift bazel
          elm submodules github_actions devcontainers
        ),
        T::Array[String]
      )

      validated_groups = groups.reject do |group|
        # Reject groups whose names match package manager names
        if reserved_names.include?(group.name.downcase.tr("-", "_"))
          Dependabot.logger.warn(
            "Group name '#{group.name}' matches a package ecosystem name and will be ignored. " \
            "Please use a different group name in your dependabot.yml configuration. " \
            "Package ecosystem names like '#{package_manager}' are reserved and cannot be used as group names."
          )
          true
        # Warn about groups with no meaningful rules (overly broad patterns that could match everything)
        elsif group.rules.empty? || (!group.rules.key?("patterns") && !group.rules.key?("dependency-type") &&
                                     !group.rules.key?("update-types"))
          Dependabot.logger.warn(
            "Group '#{group.name}' has no meaningful rules defined (no patterns, dependency-type, or update-types). " \
            "This group will match all dependencies, which may not be intended. " \
            "Please add specific rules to your dependabot.yml configuration."
          )
          # Don't reject, just warn, as this might be intentional
          false
        else
          false
        end
      end

      validated_groups
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
