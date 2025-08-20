# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/pull_request_creator/message_builder"
require "dependabot/dependency_attribution"

# This class describes a change to the project's Dependencies which has been
# determined by a Dependabot operation.
#
# It includes a list of changed Dependabot::Dependency objects, an array of
# Dependabot::DependencyFile objects which contain the changes to be applied
# along with any Dependabot::DependencyGroup that was used to generate the change.
#
# This class provides methods for presenting the change set which can be used
# by adapters to create a Pull Request, apply the changes on disk, etc.
module Dependabot
  class DependencyChange
    extend T::Sig

    class InvalidUpdatedDependencies < Dependabot::DependabotError
      extend T::Sig

      sig { params(deps_no_previous_version: T::Array[String], deps_no_change: T::Array[String]).void }
      def initialize(deps_no_previous_version:, deps_no_change:)
        msg = ""
        if deps_no_previous_version.any?
          msg += "Previous version was not provided for: '#{deps_no_previous_version.join(', ')}' "
        end
        msg += "No requirements change for: '#{deps_no_change.join(', ')}'" if deps_no_change.any?

        super(msg)
      end
    end

    sig { returns(Dependabot::Job) }
    attr_reader :job

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :updated_dependencies

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :updated_dependency_files

    sig { returns(T.nilable(Dependabot::DependencyGroup)) }
    attr_reader :dependency_group

    sig { returns(T::Array[Dependabot::Notice]) }
    attr_reader :notices

    sig do
      params(
        job: Dependabot::Job,
        updated_dependencies: T::Array[Dependabot::Dependency],
        updated_dependency_files: T::Array[Dependabot::DependencyFile],
        dependency_group: T.nilable(Dependabot::DependencyGroup),
        notices: T::Array[Dependabot::Notice]
      ).void
    end
    def initialize(job:, updated_dependencies:, updated_dependency_files:, dependency_group: nil, notices: [])
      @job = job
      @updated_dependencies = updated_dependencies
      @updated_dependency_files = updated_dependency_files
      @dependency_group = dependency_group

      @pr_message = T.let(nil, T.nilable(Dependabot::PullRequestCreator::Message))
      ensure_dependencies_have_directories
      @notices = notices
    end

    sig { returns(Dependabot::PullRequestCreator::Message) }
    def pr_message
      return @pr_message unless @pr_message.nil?

      case job.source.provider
      when "github"
        pr_message_max_length = Dependabot::PullRequestCreator::Github::PR_DESCRIPTION_MAX_LENGTH
      when "azure"
        pr_message_max_length = Dependabot::PullRequestCreator::Azure::PR_DESCRIPTION_MAX_LENGTH
        pr_message_encoding = Dependabot::PullRequestCreator::Azure::PR_DESCRIPTION_ENCODING
      when "codecommit"
        pr_message_max_length = Dependabot::PullRequestCreator::Codecommit::PR_DESCRIPTION_MAX_LENGTH
      when "bitbucket"
        pr_message_max_length = Dependabot::PullRequestCreator::Bitbucket::PR_DESCRIPTION_MAX_LENGTH
      else
        pr_message_max_length = Dependabot::PullRequestCreator::Github::PR_DESCRIPTION_MAX_LENGTH
      end

      message = Dependabot::PullRequestCreator::MessageBuilder.new(
        source: job.source,
        dependencies: updated_dependencies,
        files: updated_dependency_files,
        credentials: job.credentials,
        commit_message_options: job.commit_message_options,
        dependency_group: dependency_group,
        pr_message_max_length: pr_message_max_length,
        pr_message_encoding: pr_message_encoding,
        ignore_conditions: job.ignore_conditions,
        notices: notices
      ).message

      @pr_message = message
    end

    sig { returns(String) }
    def humanized
      updated_dependencies.map do |dependency|
        "#{dependency.name} ( from #{dependency.humanized_previous_version} to #{dependency.humanized_version} )"
      end.join(", ")
    end

    # Enhanced humanized output that includes attribution when available and feature flag is enabled
    sig { returns(String) }
    def humanized_with_attribution
      updated_dependencies.map do |dependency|
        base = "#{dependency.name} ( from #{dependency.humanized_previous_version} to #{dependency.humanized_version} )"

        attribution = DependencyAttribution.get_attribution(dependency)
        if attribution && Dependabot::Experiments.enabled?(:group_membership_enforcement)
          reason_info = "[#{attribution[:selection_reason]}, group: #{attribution[:source_group]}]"
          "#{base} #{reason_info}"
        else
          base
        end
      end.join(", ")
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def updated_dependency_files_hash
      updated_dependency_files.map(&:to_h)
    end

    sig { returns(T::Boolean) }
    def grouped_update?
      !!dependency_group
    end

    # This method combines checking the job's `updating_a_pull_request` flag
    # with verification the dependencies involved remain the same.
    #
    # If the dependencies involved have changed, we should close the old PR
    # rather than supersede it as the new changes don't necessarily follow
    # from the previous ones; dependencies could have been removed from the
    # project, or pinned by other changes.
    sig { returns(T::Boolean) }
    def should_replace_existing_pr?
      return false unless job.updating_a_pull_request?

      # NOTE: Gradle, Maven and Nuget dependency names can be case-insensitive
      # and the dependency name injected from a security advisory often doesn't
      # match what users have specified in their manifest.
      updated_dependencies.map { |x| x.name.downcase }.uniq.sort != T.must(job.dependencies).map(&:downcase).uniq.sort
    end

    sig { params(dependency_changes: T::Array[DependencyChange]).void }
    def merge_changes!(dependency_changes)
      dependency_changes.each do |dependency_change|
        updated_dependencies.concat(dependency_change.updated_dependencies)
        updated_dependency_files.concat(dependency_change.updated_dependency_files)
        notices.concat(dependency_change.notices)
      end
      updated_dependencies.compact!
      updated_dependency_files.compact!
      notices.compact!
    end

    sig { returns(T::Boolean) }
    def all_have_previous_version?
      return true if updated_dependencies.all?(&:requirements_changed?)
      return true if updated_dependencies.all?(&:previous_version)

      false
    end

    sig { void }
    def check_dependencies_have_previous_version
      return if all_have_previous_version?

      deps_no_previous_version = updated_dependencies.reject(&:previous_version)
      deps_no_change = updated_dependencies.reject(&:requirements_changed?)
      raise InvalidUpdatedDependencies.new(
        deps_no_previous_version: deps_no_previous_version.map(&:name),
        deps_no_change: deps_no_change.map(&:name)
      )
    end

    sig { returns(T::Boolean) }
    def matches_existing_pr?
      if grouped_update?
        # We only want PRs for the same group that have the same versions
        job.existing_group_pull_requests.any? do |pr|
          directories_in_use = pr["dependencies"].all? { |dep| dep["directory"] }

          pr["dependency-group-name"] == dependency_group&.name &&
            Set.new(pr["dependencies"]) == updated_dependencies_set(should_consider_directory: directories_in_use)
        end
      else
        job.existing_pull_requests.any?(new_pr)
      end
    end

    # Attribution and observability methods

    # Get attribution summary for this change's dependencies
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def attribution_summary
      DependencyAttribution.telemetry_summary(updated_dependencies)
    end

    # Get detailed attribution data for debugging
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def attribution_details
      DependencyAttribution.extract_attribution_data(updated_dependencies)
    end

    # Check if any dependencies have attribution metadata
    sig { returns(T::Boolean) }
    def attributed_dependencies?
      updated_dependencies.any? { |dep| DependencyAttribution.attributed?(dep) }
    end

    # Get dependencies grouped by selection reason
    sig { returns(T::Hash[Symbol, T::Array[Dependabot::Dependency]]) }
    def dependencies_by_selection_reason
      result = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[Symbol, T::Array[Dependabot::Dependency]])

      updated_dependencies.each do |dep|
        attribution = DependencyAttribution.get_attribution(dep)
        reason = attribution ? attribution[:selection_reason] : :unknown
        T.must(result[reason]) << dep
      end

      result
    end

    # Get filtered dependencies for observability (set by GroupDependencySelector)
    sig { returns(T.nilable(T::Array[Dependabot::Dependency])) }
    def filtered_dependencies
      instance_variable_get(:@filtered_dependencies)
    end

    # Get dependency drift for observability (set by GroupDependencySelector)
    sig { returns(T.nilable(T::Array[String])) }
    def dependency_drift
      instance_variable_get(:@dependency_drift)
    end

    # Log attribution details for debugging
    sig { void }
    def log_attribution_details
      return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)
      return unless attributed_dependencies?

      summary = attribution_summary
      Dependabot.logger.info(
        "DependencyChange attribution summary: #{summary['attributed_dependencies']}/#{summary['total_dependencies']} dependencies attributed " \
        "[coverage=#{(summary['attribution_coverage'] * 100).round(1)}%]"
      )

      # Log selection reason breakdown
      if summary["selection_reasons"].any?
        reasons = summary["selection_reasons"].map { |reason, count| "#{reason}:#{count}" }.join(", ")
        Dependabot.logger.debug("Selection reasons: #{reasons}")
      end

      # Log any filtered dependencies
      if filtered_dependencies&.any?
        filtered_names = filtered_dependencies&.map(&:name)&.join(", ")
        Dependabot.logger.debug("Filtered dependencies: #{filtered_names}")
      end

      # Log any dependency drift
      return unless dependency_drift&.any?

      Dependabot.logger.debug("Dependency drift detected: #{dependency_drift&.join(', ')}")
    end

    # Export attribution data for telemetry systems
    sig { returns(T::Hash[String, T.untyped]) }
    def export_attribution_telemetry
      return {} unless Dependabot::Experiments.enabled?(:group_membership_enforcement)
      return {} unless attributed_dependencies?

      {
        dependency_change_id: object_id,
        group_name: dependency_group&.name,
        ecosystem: job.source.directory || "unknown", # This might need refinement
        attribution_summary: attribution_summary,
        attribution_details: attribution_details,
        filtered_count: filtered_dependencies&.length || 0,
        dependency_drift_count: dependency_drift&.length || 0,
        total_files_changed: updated_dependency_files.length,
        timestamp: Time.now.utc.iso8601
      }
    end

    private

    # Older PRs will not have a directory key, in that case do not consider directory in the comparison. This will
    # allow rebases to continue working for those, but for multi-directory configs we do compare with the directory.
    sig { params(should_consider_directory: T::Boolean).returns(T::Set[T::Hash[String, T.any(String, T::Boolean)]]) }
    def updated_dependencies_set(should_consider_directory:)
      Set.new(
        updated_dependencies.map do |dep|
          {
            "dependency-name" => dep.name,
            "dependency-version" => dep.version,
            "directory" => should_consider_directory ? dep.directory : nil,
            "dependency-removed" => dep.removed? ? true : nil
          }.compact
        end
      )
    end

    sig { returns(PullRequest) }
    def new_pr
      @new_pr ||= T.let(PullRequest.create_from_updated_dependencies(updated_dependencies),
                        T.nilable(Dependabot::PullRequest))
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def ensure_dependencies_have_directories
      updated_dependencies.each do |dep|
        dep.directory = directory
      end
    end

    sig { returns(String) }
    def directory
      return "" if updated_dependency_files.empty?

      T.must(updated_dependency_files.first).directory
    end
  end
end
