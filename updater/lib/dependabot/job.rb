# typed: strict
# frozen_string_literal: true

require "wildcard_matcher"

require "dependabot/config/ignore_condition"
require "dependabot/config/update_config"
require "dependabot/credential"
require "dependabot/dependency_group_engine"
require "dependabot/experiments"
require "dependabot/requirements_update_strategy"
require "dependabot/source"

# Describes a single Dependabot workload within the GitHub-integrated Service
#
# This primarily acts as a value class to hold inputs for various Core objects
# and is an approximate data structure for the 'job description file' used by
# the CLI tool.
#
# See: https://github.com/dependabot/cli#job-description-file
#
# This class should eventually be promoted to common/lib and augmented to
# validate job description files.
module Dependabot
  class Job
    extend T::Sig

    TOP_LEVEL_DEPENDENCY_TYPES = T.let(%w(direct production development).freeze, T::Array[String])
    PERMITTED_KEYS = T.let(%i(
      allowed_updates
      commit_message_options
      dependencies
      existing_pull_requests
      existing_group_pull_requests
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
      dependency_groups
      dependency_group_to_refresh
      repo_private
    ).freeze, T::Array[Symbol])

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    attr_reader :allowed_updates

    sig { returns(T::Array[Dependabot::Credential]) }
    attr_reader :credentials

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :dependencies

    sig { returns(T::Array[T::Array[T::Hash[String, String]]]) }
    attr_reader :existing_pull_requests

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    attr_reader :existing_group_pull_requests

    sig { returns(String) }
    attr_reader :id

    sig { returns(T::Array[T.untyped]) }
    attr_reader :ignore_conditions

    sig { returns(String) }
    attr_reader :package_manager

    sig { returns(T.nilable(Dependabot::RequirementsUpdateStrategy)) }
    attr_reader :requirements_update_strategy

    sig { returns(T::Array[T.untyped]) }
    attr_reader :security_advisories

    sig { returns(T::Boolean) }
    attr_reader :security_updates_only

    sig { returns(Dependabot::Source) }
    attr_reader :source

    sig { returns(T.nilable(String)) }
    attr_reader :token

    sig { returns(T::Boolean) }
    attr_reader :vendor_dependencies

    sig { returns(T::Array[T.untyped]) }
    attr_reader :dependency_groups

    sig { returns(T.nilable(String)) }
    attr_reader :dependency_group_to_refresh

    sig do
      params(job_id: String, job_definition: T::Hash[String, T.untyped],
             repo_contents_path: T.nilable(String)).returns(Job)
    end
    def self.new_fetch_job(job_id:, job_definition:, repo_contents_path: nil)
      attrs = standardise_keys(job_definition["job"]).select { |k, _| PERMITTED_KEYS.include?(k) }

      new(attrs.merge(id: job_id, repo_contents_path: repo_contents_path))
    end

    sig do
      params(job_id: String, job_definition: T::Hash[String, T.untyped],
             repo_contents_path: T.nilable(String)).returns(Job)
    end
    def self.new_update_job(job_id:, job_definition:, repo_contents_path: nil)
      job_hash = standardise_keys(job_definition["job"])
      attrs = job_hash.select { |k, _| PERMITTED_KEYS.include?(k) }
      attrs[:credentials] = job_hash[:credentials_metadata] || []

      new(attrs.merge(id: job_id, repo_contents_path: repo_contents_path))
    end

    sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def self.standardise_keys(hash)
      hash.transform_keys { |key| key.tr("-", "_").to_sym }
    end

    # NOTE: "attributes" are fetched and injected at run time from
    # dependabot-api using the UpdateJobPrivateSerializer
    sig { params(attributes: T.untyped).void }
    def initialize(attributes) # rubocop:disable Metrics/AbcSize
      @id                             = T.let(attributes.fetch(:id), String)
      @allowed_updates                = T.let(attributes.fetch(:allowed_updates), T::Array[T.untyped])
      @commit_message_options         = T.let(attributes.fetch(:commit_message_options, {}),
                                              T.nilable(T::Hash[T.untyped, T.untyped]))
      @credentials                    = T.let(attributes.fetch(:credentials, []).map do |data|
                                                Dependabot::Credential.new(data)
                                              end,
                                              T::Array[Dependabot::Credential])
      @dependencies                   = T.let(attributes.fetch(:dependencies), T.nilable(T::Array[T.untyped]))
      @existing_pull_requests         = T.let(attributes.fetch(:existing_pull_requests),
                                              T::Array[T::Array[T::Hash[String, String]]])
      # TODO: Make this hash required
      #
      # We will need to do a pass updating the CLI and smoke tests before this is possible,
      # so let's consider it optional for now. If we get a nil value, let's force it to be
      # an array.
      @existing_group_pull_requests   =  T.let(attributes.fetch(:existing_group_pull_requests, []) || [],
                                               T::Array[T::Hash[String, T.untyped]])
      @experiments                    =  T.let(attributes.fetch(:experiments, {}),
                                               T.nilable(T::Hash[T.untyped, T.untyped]))
      @ignore_conditions              =  T.let(attributes.fetch(:ignore_conditions), T::Array[T.untyped])
      @package_manager                =  T.let(attributes.fetch(:package_manager), String)
      @reject_external_code           =  T.let(attributes.fetch(:reject_external_code, false), T::Boolean)
      @repo_contents_path             =  T.let(attributes.fetch(:repo_contents_path, nil), T.nilable(String))

      @requirements_update_strategy   = T.let(build_update_strategy(
                                                **attributes.slice(:requirements_update_strategy, :lockfile_only)
                                              ), T.nilable(Dependabot::RequirementsUpdateStrategy))

      @security_advisories            = T.let(attributes.fetch(:security_advisories), T::Array[T.untyped])
      @security_updates_only          = T.let(attributes.fetch(:security_updates_only), T::Boolean)
      @source                         = T.let(build_source(attributes.fetch(:source)), Dependabot::Source)
      @token                          = T.let(attributes.fetch(:token, nil), T.nilable(String))
      @update_subdependencies         = T.let(attributes.fetch(:update_subdependencies), T::Boolean)
      @updating_a_pull_request        = T.let(attributes.fetch(:updating_a_pull_request), T::Boolean)
      @vendor_dependencies            = T.let(attributes.fetch(:vendor_dependencies, false), T::Boolean)
      # TODO: Make this hash required
      #
      # We will need to do a pass updating the CLI and smoke tests before this is possible,
      # so let's consider it optional for now. If we get a nil value, let's force it to be
      # an array.
      @dependency_groups              = T.let(attributes.fetch(:dependency_groups, []) || [], T::Array[T.untyped])
      @dependency_group_to_refresh    = T.let(attributes.fetch(:dependency_group_to_refresh, nil), T.nilable(String))
      @repo_private                   = T.let(attributes.fetch(:repo_private, nil), T.nilable(T::Boolean))

      @update_config = T.let(calculate_update_config, Dependabot::Config::UpdateConfig)

      register_experiments
      validate_job
    end

    sig { returns(T::Boolean) }
    def clone?
      true
    end

    # Some Core components test for a non-nil repo_contents_path as an implicit
    # signal they should use cloning behaviour, so we present it as nil unless
    # cloning is enabled to avoid unexpected behaviour.
    sig { returns(T.nilable(String)) }
    def repo_contents_path
      return nil unless clone?

      @repo_contents_path
    end

    sig { returns(T.nilable(T::Boolean)) }
    def repo_private?
      @repo_private
    end

    sig { returns(T.nilable(String)) }
    def repo_owner
      source.organization
    end

    sig { returns(T::Boolean) }
    def updating_a_pull_request?
      @updating_a_pull_request
    end

    sig { returns(T::Boolean) }
    def update_subdependencies?
      @update_subdependencies
    end

    sig { returns(T::Boolean) }
    def security_updates_only?
      @security_updates_only
    end

    sig { returns(T::Boolean) }
    def vendor_dependencies?
      @vendor_dependencies
    end

    sig { returns(T::Boolean) }
    def reject_external_code?
      @reject_external_code
    end

    # TODO: Remove vulnerability checking
    #
    # This method does too much, let's make it focused on _just_ determining
    # if the given dependency is within the configurations allowed_updates.
    #
    # The calling operation should be responsible for checking vulnerability
    # separately, if required.
    #
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    sig { params(dependency: Dependency).returns(T::Boolean) }
    def allowed_update?(dependency)
      # Ignoring all versions is another way to say no updates allowed
      if completely_ignored?(dependency)
        Dependabot.logger.info("All versions of #{dependency.name} ignored, no update allowed")
        return false
      end

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
    # rubocop:enable Metrics/CyclomaticComplexity

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def vulnerable?(dependency)
      security_advisories = security_advisories_for(dependency)
      return false if security_advisories.none?

      # Can't (currently) detect whether dependencies without a version
      # (i.e., for repos without a lockfile) are vulnerable
      return false unless dependency.version

      # Can't (currently) detect whether git dependencies are vulnerable
      version_class =
        Dependabot::Utils
        .version_class_for_package_manager(dependency.package_manager)
      return false unless version_class.correct?(dependency.version)

      all_versions = dependency.all_versions
                               .filter_map { |v| version_class.new(v) if version_class.correct?(v) }
      security_advisories.any? { |a| all_versions.any? { |v| a.vulnerable?(v) } }
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def security_fix?(dependency)
      security_advisories_for(dependency).any? { |a| a.fixed_by?(dependency) }
    end

    sig { returns(T.nilable(T.proc.params(arg0: String).returns(String))) }
    def name_normaliser
      Dependabot::Dependency.name_normaliser_for_package_manager(package_manager)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def experiments
      return {} unless @experiments

      self.class.standardise_keys(@experiments)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def commit_message_options
      return {} unless @commit_message_options

      self.class.standardise_keys(@commit_message_options).compact
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::SecurityAdvisory]) }
    def security_advisories_for(dependency)
      relevant_advisories =
        security_advisories
        .select { |adv| adv.fetch("dependency-name").casecmp(dependency.name).zero? }

      relevant_advisories.map do |adv|
        vulnerable_versions = adv["affected-versions"] || []
        safe_versions = (adv["patched-versions"] || []) +
                        (adv["unaffected-versions"] || [])

        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency.name,
          package_manager: package_manager,
          vulnerable_versions: vulnerable_versions,
          safe_versions: safe_versions
        )
      end
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
    def ignore_conditions_for(dependency)
      update_config.ignored_versions_for(
        dependency,
        security_updates_only: security_updates_only?
      )
    end

    # TODO: Present Dependabot::Config::IgnoreCondition in calling code
    #
    # This is a workaround for our existing logging using the 'raw'
    # ignore conditions passed into the job definition rather than
    # the objects returned by `ignore_conditions_for`.
    #
    # The blocker on adopting Dependabot::Config::IgnoreCondition is
    # that it does not have a 'source' attribute which we currently
    # use to distinguish rules from the config file from those that
    # were created via "@dependabot ignore version" commands
    sig { params(dependency: Dependabot::Dependency).void }
    def log_ignore_conditions_for(dependency)
      conditions = ignore_conditions.select { |ic| name_match?(ic["dependency-name"], dependency.name) }
      return if conditions.empty?

      Dependabot.logger.info("Ignored versions:")
      conditions.each do |ic|
        unless ic["version-requirement"].nil?
          Dependabot.logger.info("  #{ic['version-requirement']} - from #{ic['source']}")
        end

        ic["update-types"]&.each do |update_type|
          msg = "  #{update_type} - from #{ic['source']}"
          msg += " (doesn't apply to security update)" if security_updates_only?
          Dependabot.logger.info(msg)
        end
      end
    end

    # Remove this once the API always sends groups for grouped refresh jobs
    sig { params(group: String).void }
    def override_group_to_refresh_due_to_old_defaults(group)
      @dependency_group_to_refresh = group
    end

    private

    sig { returns(Dependabot::Config::UpdateConfig) }
    attr_reader :update_config

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def completely_ignored?(dependency)
      ignore_conditions_for(dependency).any?(Dependabot::Config::IgnoreCondition::ALL_VERSIONS)
    end

    sig { void }
    def register_experiments
      experiments.entries.each do |name, value|
        Dependabot::Experiments.register(name, value)
      end
    end

    sig { void }
    def validate_job
      raise "Either directory or directories must be provided" unless source.directory.nil? ^ source.directories.nil?
    end

    sig { params(name1: String, name2: String).returns(T::Boolean) }
    def name_match?(name1, name2)
      WildcardMatcher.match?(
        T.must(name_normaliser).call(name1),
        T.must(name_normaliser).call(name2)
      )
    end

    sig do
      params(
        requirements_update_strategy: T.nilable(String),
        lockfile_only: T::Boolean
      )
        .returns(T.nilable(Dependabot::RequirementsUpdateStrategy))
    end
    def build_update_strategy(requirements_update_strategy:, lockfile_only:)
      unless requirements_update_strategy.nil?
        return RequirementsUpdateStrategy.deserialize(requirements_update_strategy)
      end

      lockfile_only ? RequirementsUpdateStrategy::LockfileOnly : nil
    end

    sig { params(source_details: T::Hash[String, T.untyped]).returns(Dependabot::Source) }
    def build_source(source_details)
      # Immediately normalize the source directory, ensure it starts with a "/"
      directory, directories = clean_directories(source_details)

      Dependabot::Source.new(
        provider: T.let(source_details["provider"], String),
        repo: T.let(source_details["repo"], String),
        directory: directory,
        directories: directories,
        branch: T.let(source_details["branch"], T.nilable(String)),
        commit: T.let(source_details["commit"], T.nilable(String)),
        hostname: T.let(source_details["hostname"], T.nilable(String)),
        api_endpoint: T.let(source_details["api-endpoint"], T.nilable(String))
      )
    end

    sig { params(source_details: T::Hash[String, T.untyped]).returns([T.nilable(String), T.nilable(T::Array[String])]) }
    def clean_directories(source_details)
      directory = T.let(source_details["directory"], T.nilable(String))
      unless directory.nil?
        directory = Pathname.new(directory).cleanpath.to_s
        directory = "/#{directory}" unless directory.start_with?("/")
      end
      directories = T.let(source_details["directories"], T.nilable(T::Array[String]))
      unless directories.nil?
        directories = directories.map do |dir|
          dir = Pathname.new(dir).cleanpath.to_s
          dir = "/#{dir}" unless dir.start_with?("/")
          dir
        end
      end
      [directory, directories]
    end

    # Provides a Dependabot::Config::UpdateConfig objected hydrated with
    # relevant information obtained from the job definition.
    #
    # At present we only use this for ignore rules.
    sig { returns(Dependabot::Config::UpdateConfig) }
    def calculate_update_config
      update_config_ignore_conditions = ignore_conditions.map do |ic|
        Dependabot::Config::IgnoreCondition.new(
          dependency_name: T.let(ic["dependency-name"], String),
          versions: T.let([ic["version-requirement"]].compact, T::Array[String]),
          update_types: T.let(ic["update-types"], T.nilable(T::Array[String]))
        )
      end

      update_config = Dependabot::Config::UpdateConfig.new(
        ignore_conditions: T.let(update_config_ignore_conditions, T::Array[Dependabot::Config::IgnoreCondition])
      )
      T.let(update_config, Dependabot::Config::UpdateConfig)
    end
  end
end
