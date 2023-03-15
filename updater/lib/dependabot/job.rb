# frozen_string_literal: true

require "dependabot/experiments"
require "dependabot/source"
require "wildcard_matcher"

# Describes a single Dependabot workload within the GitHub-integrated Service
#
# This primarily acts as a value class to hold inputs for various Core objects
# and is an approximate data structure for the 'job description file' used by
# the CLI tool.
#
# See: https://github.com/dependabot/cli#job-description-file
#
# This class should evenually be promoted to common/lib and augmented to
# validate job description files.
module Dependabot
  class Job
    TOP_LEVEL_DEPENDENCY_TYPES = %w(direct production development).freeze
    PERMITTED_KEYS = %i(
      allowed_updates
      commit_message_options
      dependencies
      existing_pull_requests
      experiments
      ignore_conditions
      lockfile_only
      package_manager
      reject_external_code
      repo_contents_path
      requirements_update_strategy
      security_advisories
      security_updates_only
      source
      update_subdependencies
      updating_a_pull_request
      vendor_dependencies
    )

    attr_reader :allowed_updates,
                :credentials,
                :dependencies,
                :existing_pull_requests,
                :id,
                :ignore_conditions,
                :package_manager,
                :requirements_update_strategy,
                :security_advisories,
                :security_updates_only,
                :source,
                :token,
                :vendor_dependencies

    def self.new_fetch_job(job_id:, job_definition:, repo_contents_path: nil)
      attrs = standardise_keys(job_definition["job"]).slice(*PERMITTED_KEYS)

      new(attrs.merge(id: job_id, repo_contents_path: repo_contents_path))
    end

    def self.new_update_job(job_id:, job_definition:, repo_contents_path: nil)
      attrs = standardise_keys(job_definition["job"]).tap do |job_hash|
        # The Updater should NOT have access to credentials. Let's use metadata, which
        # can be used by the proxy for matching and applying the real credentials
        job_hash[:credentials] = job_hash.delete(:credentials_metadata) || []
      end.slice(*PERMITTED_KEYS)

      new(attrs.merge(id: job_id, repo_contents_path: repo_contents_path))
    end

    def self.standardise_keys(hash)
      hash.transform_keys { |key| key.tr("-", "_").to_sym }
    end

    # NOTE: "attributes" are fetched and injected at run time from
    # dependabot-api using the UpdateJobPrivateSerializer
    def initialize(attributes)
      @id                           = attributes.fetch(:id)
      @allowed_updates              = attributes.fetch(:allowed_updates)
      @commit_message_options       = attributes.fetch(:commit_message_options, {})
      @credentials                  = attributes.fetch(:credentials, [])
      @dependencies                 = attributes.fetch(:dependencies)
      @existing_pull_requests       = attributes.fetch(:existing_pull_requests)
      @experiments                  = attributes.fetch(:experiments, {})
      @ignore_conditions            = attributes.fetch(:ignore_conditions)
      @lockfile_only                = attributes.fetch(:lockfile_only)
      @package_manager              = attributes.fetch(:package_manager)
      @reject_external_code         = attributes.fetch(:reject_external_code, false)
      @repo_contents_path           = attributes.fetch(:repo_contents_path, nil)
      @requirements_update_strategy = attributes.fetch(:requirements_update_strategy)
      @security_advisories          = attributes.fetch(:security_advisories)
      @security_updates_only        = attributes.fetch(:security_updates_only)
      @source                       = build_source(attributes.fetch(:source))
      @token                        = attributes.fetch(:token, nil)
      @update_subdependencies       = attributes.fetch(:update_subdependencies)
      @updating_a_pull_request      = attributes.fetch(:updating_a_pull_request)
      @vendor_dependencies          = attributes.fetch(:vendor_dependencies, false)

      register_experiments
    end

    def clone?
      vendor_dependencies? ||
        Dependabot::Utils.always_clone_for_package_manager?(@package_manager)
    end

    # Some Core components test for a non-nil repo_contents_path as an implicit
    # signal they should use cloning behaviour, so we present it as nil unless
    # cloning is enabled to avoid unexpected behaviour.
    def repo_contents_path
      return nil unless clone?

      @repo_contents_path
    end

    def lockfile_only?
      @lockfile_only
    end

    def updating_a_pull_request?
      @updating_a_pull_request
    end

    def update_subdependencies?
      @update_subdependencies
    end

    def security_updates_only?
      @security_updates_only
    end

    def vendor_dependencies?
      @vendor_dependencies
    end

    def reject_external_code?
      @reject_external_code
    end

    # rubocop:disable Metrics/PerceivedComplexity
    def allowed_update?(dependency)
      allowed_updates.any? do |update|
        # Check the update-type (defaulting to all)
        update_type = update.fetch("update-type", "all")
        # NOTE: Preview supports specifying a "security" update type whereas
        # native will say "security-updates-only"
        security_update = update_type == "security" || security_updates_only?
        next false if security_update && !vulnerable?(dependency)

        # Check the dependency-name (defaulting to matching)
        condition_name = update.fetch("dependency-name", dependency.name)
        next false unless name_match?(condition_name, dependency.name)

        # Check the dependency-type (defaulting to all)
        dep_type = update.fetch("dependency-type", "all")
        next false if dep_type == "indirect" &&
                      dependency.requirements.any?
        # In dependabot-api, dependency-type is defaulting to "direct" not "all". Ignoring
        # that field for security updates, since it should probably be "all".
        next false if !security_updates_only &&
                      dependency.requirements.none? &&
                      TOP_LEVEL_DEPENDENCY_TYPES.include?(dep_type)
        next false if dependency.production? && dep_type == "development"
        next false if !dependency.production? && dep_type == "production"

        true
      end
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def vulnerable?(dependency)
      security_advisories = security_advisories_for(dependency)
      return false if security_advisories.none?

      # Can't (currently) detect whether dependencies without a version
      # (i.e., for repos without a lockfile) are vulnerable
      return false unless dependency.version

      # Can't (currently) detect whether git dependencies are vulnerable
      version_class =
        Dependabot::Utils.
        version_class_for_package_manager(dependency.package_manager)
      return false unless version_class.correct?(dependency.version)

      all_versions = dependency.all_versions.
                     filter_map { |v| version_class.new(v) if version_class.correct?(v) }
      security_advisories.any? { |a| all_versions.any? { |v| a.vulnerable?(v) } }
    end

    def security_fix?(dependency)
      security_advisories_for(dependency).any? { |a| a.fixed_by?(dependency) }
    end

    def name_normaliser
      Dependabot::Dependency.name_normaliser_for_package_manager(package_manager)
    end

    def experiments
      return {} unless @experiments

      self.class.standardise_keys(@experiments)
    end

    def commit_message_options
      return {} unless @commit_message_options

      self.class.standardise_keys(@commit_message_options).compact
    end

    private

    def register_experiments
      experiments.each do |name, value|
        Dependabot::Experiments.register(name, value)
      end
    end

    def name_match?(name1, name2)
      WildcardMatcher.match?(
        name_normaliser.call(name1),
        name_normaliser.call(name2)
      )
    end

    def build_source(source_details)
      Dependabot::Source.new(
        **source_details.transform_keys { |k| k.tr("-", "_").to_sym }
      )
    end

    def security_advisories_for(dep)
      relevant_advisories =
        security_advisories.
        select { |adv| adv.fetch("dependency-name").casecmp(dep.name).zero? }

      relevant_advisories.map do |adv|
        vulnerable_versions = adv["affected-versions"] || []
        safe_versions = (adv["patched-versions"] || []) +
                        (adv["unaffected-versions"] || [])

        Dependabot::SecurityAdvisory.new(
          dependency_name: dep.name,
          package_manager: package_manager,
          vulnerable_versions: vulnerable_versions,
          safe_versions: safe_versions
        )
      end
    end
  end
end
