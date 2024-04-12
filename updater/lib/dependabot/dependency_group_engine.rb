# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_group"

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
    def self.from_job_config(job:) # rubocop:disable Metrics/PerceivedComplexity
      if job.security_updates_only? && T.must(job.dependencies).count > 1 && job.dependency_groups.none? do |group|
           group["applies-to"] == "security-updates"
         end
        # The indication that this should be a grouped update is:
        # - We're using the DependencyGroupEngine which means this is a grouped update
        # - This is a security update and there are multiple dependencies passed in
        # Since there are no groups, the default behavior is to group all dependencies, so create a fake group.
        #
        # The service doesn't have record of this group, but makes similar assumptions.
        # If we change this, we need to update the service to match.
        #
        # See: https://github.com/dependabot/dependabot-core/issues/9426
        job.dependency_groups << {
          "name" => job.package_manager,
          "rules" => { "patterns" => ["*"] },
          "applies-to" => "security-updates"
        }

        # This ensures refreshes work for these dynamic groups.
        if job.updating_a_pull_request?
          job.override_group_to_refresh_due_to_old_defaults(job.dependency_groups.first["name"])
        end
      end

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
        dependencies.each do |dependency|
          matched_groups = @dependency_groups.each_with_object([]) do |group, matches|
            next unless group.contains?(dependency)

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
  end
end
