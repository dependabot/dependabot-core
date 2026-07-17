# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/pull_request"
require "dependabot/job/allowed_update"
require "dependabot/job/blocked_version"
require "dependabot/job/dependency_group_definition"
require "dependabot/job/existing_group_pull_request"
require "dependabot/job/ignore_condition"
require "dependabot/job/security_advisory_entry"
require "dependabot/job/source_definition"

module Dependabot
  class Job
    # Parsed representation of the top-level job attributes.
    class Definition < T::ImmutableStruct
      extend T::Sig

      const :id, String
      const :command, String
      const :allowed_updates, T::Array[AllowedUpdate]
      const :commit_message_options, T.nilable(T::Hash[String, Object])
      const :credentials, T::Array[Dependabot::Credential]
      const :dependencies, T.nilable(T::Array[String])
      const :exclude_paths, T.nilable(T::Array[String])
      const :existing_pull_requests, T::Array[Dependabot::PullRequest]
      const :existing_group_pull_requests, T::Array[ExistingGroupPullRequest]
      const :experiments, T.nilable(T::Hash[String, Object])
      const :ignore_conditions, T::Array[IgnoreCondition]
      const :package_manager, String
      const :reject_external_code, T::Boolean
      const :repo_contents_path, T.nilable(String)
      const :requirements_update_strategy, T.nilable(String)
      const :lockfile_only, T::Boolean
      const :security_advisories, T::Array[SecurityAdvisoryEntry]
      const :security_updates_only, T::Boolean
      const :source, SourceDefinition
      const :token, T.nilable(String)
      const :update_subdependencies, T::Boolean
      const :updating_a_pull_request, T::Boolean
      const :vendor_dependencies, T::Boolean
      const :cooldown, T.nilable(T::Hash[String, Object])
      const :multi_ecosystem_update, T::Boolean
      const :dependency_groups, T::Array[DependencyGroupDefinition]
      const :dependency_group_to_refresh, T.nilable(String)
      const :repo_private, T.nilable(T::Boolean)
      const :blocked_versions, T::Array[BlockedVersion]

      # Keep the complete wire-to-model mapping visible in one place so new job fields cannot bypass parsing.
      # rubocop:disable Metrics/AbcSize
      sig { params(hash: T::Hash[Symbol, Object]).returns(Definition) }
      def self.from_hash(hash)
        new(
          id: required_string(hash, :id),
          command: string_with_default(hash, :command, ""),
          allowed_updates: parsed_allowed_updates(hash),
          commit_message_options: parsed_commit_message_options(hash),
          credentials: parsed_credentials(hash),
          dependencies: optional_string_array(hash.fetch(:dependencies), :dependencies),
          exclude_paths: optional_string_array(hash.fetch(:exclude_paths, []), :exclude_paths),
          existing_pull_requests: Dependabot::PullRequest.create_from_job_definition(hash),
          existing_group_pull_requests: parsed_existing_group_pull_requests(hash),
          experiments: optional_string_hash(hash.fetch(:experiments, nil), :experiments),
          ignore_conditions: parsed_ignore_conditions(hash),
          package_manager: required_string(hash, :package_manager),
          reject_external_code: boolean_with_default(hash, :reject_external_code, false),
          repo_contents_path: optional_string(hash.fetch(:repo_contents_path, nil), :repo_contents_path),
          requirements_update_strategy: parsed_requirements_update_strategy(hash),
          lockfile_only: required_boolean(hash, :lockfile_only),
          security_advisories: parsed_security_advisories(hash),
          security_updates_only: required_boolean(hash, :security_updates_only),
          source: parsed_source(hash),
          token: optional_string(hash.fetch(:token, nil), :token),
          update_subdependencies: required_boolean(hash, :update_subdependencies),
          updating_a_pull_request: required_boolean(hash, :updating_a_pull_request),
          vendor_dependencies: boolean_with_default(hash, :vendor_dependencies, false),
          cooldown: optional_string_hash(hash.fetch(:cooldown, nil), :cooldown),
          multi_ecosystem_update: boolean_with_default(hash, :multi_ecosystem_update, false),
          dependency_groups: parsed_dependency_groups(hash),
          dependency_group_to_refresh: parsed_dependency_group_to_refresh(hash),
          repo_private: optional_boolean(hash.fetch(:repo_private, nil), :repo_private),
          blocked_versions: parsed_blocked_versions(hash)
        )
      end
      # rubocop:enable Metrics/AbcSize

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[AllowedUpdate]) }
      def self.parsed_allowed_updates(hash)
        strict_hash_array(hash.fetch(:allowed_updates), :allowed_updates)
          .map { |entry| AllowedUpdate.from_hash(entry) }
      end
      private_class_method :parsed_allowed_updates

      sig { params(hash: T::Hash[Symbol, Object]).returns(T.nilable(T::Hash[String, Object])) }
      def self.parsed_commit_message_options(hash)
        optional_string_hash(hash.fetch(:commit_message_options, nil), :commit_message_options)
      end
      private_class_method :parsed_commit_message_options

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[Dependabot::Credential]) }
      def self.parsed_credentials(hash)
        credentials(hash.fetch(:credentials, []))
      end
      private_class_method :parsed_credentials

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[ExistingGroupPullRequest]) }
      def self.parsed_existing_group_pull_requests(hash)
        tolerant_hash_array(
          hash.fetch(:existing_group_pull_requests, []) || [],
          :existing_group_pull_requests
        ).map { |entry| ExistingGroupPullRequest.from_hash(entry) }
      end
      private_class_method :parsed_existing_group_pull_requests

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[IgnoreCondition]) }
      def self.parsed_ignore_conditions(hash)
        strict_hash_array(hash.fetch(:ignore_conditions), :ignore_conditions)
          .map { |entry| IgnoreCondition.from_hash(entry) }
      end
      private_class_method :parsed_ignore_conditions

      sig { params(hash: T::Hash[Symbol, Object]).returns(T.nilable(String)) }
      def self.parsed_requirements_update_strategy(hash)
        optional_string(hash.fetch(:requirements_update_strategy), :requirements_update_strategy)
      end
      private_class_method :parsed_requirements_update_strategy

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[SecurityAdvisoryEntry]) }
      def self.parsed_security_advisories(hash)
        strict_hash_array(hash.fetch(:security_advisories), :security_advisories)
          .map { |entry| SecurityAdvisoryEntry.from_hash(entry) }
      end
      private_class_method :parsed_security_advisories

      sig { params(hash: T::Hash[Symbol, Object]).returns(SourceDefinition) }
      def self.parsed_source(hash)
        SourceDefinition.from_hash(required_string_hash(hash.fetch(:source), :source))
      end
      private_class_method :parsed_source

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[DependencyGroupDefinition]) }
      def self.parsed_dependency_groups(hash)
        tolerant_hash_array(
          hash.fetch(:dependency_groups, []) || [],
          :dependency_groups
        ).map { |entry| DependencyGroupDefinition.from_hash(entry) }
      end
      private_class_method :parsed_dependency_groups

      sig { params(hash: T::Hash[Symbol, Object]).returns(T.nilable(String)) }
      def self.parsed_dependency_group_to_refresh(hash)
        optional_string(hash.fetch(:dependency_group_to_refresh, nil), :dependency_group_to_refresh)
      end
      private_class_method :parsed_dependency_group_to_refresh

      sig { params(hash: T::Hash[Symbol, Object]).returns(T::Array[BlockedVersion]) }
      def self.parsed_blocked_versions(hash)
        tolerant_hash_array(
          hash.fetch(:blocked_versions, []) || [],
          :blocked_versions
        ).map { |entry| BlockedVersion.from_hash(entry) }
      end
      private_class_method :parsed_blocked_versions

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(String) }
      def self.required_string(hash, key)
        value = hash.fetch(key)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :required_string

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol, default: String).returns(String) }
      def self.string_with_default(hash, key, default)
        value = hash.fetch(key, default)
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :string_with_default

      sig { params(value: T.nilable(Object), key: Symbol).returns(T.nilable(String)) }
      def self.optional_string(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be a string" unless value.is_a?(String)

        value
      end
      private_class_method :optional_string

      sig { params(hash: T::Hash[Symbol, Object], key: Symbol).returns(T::Boolean) }
      def self.required_boolean(hash, key)
        boolean_value(hash.fetch(key), key)
      end
      private_class_method :required_boolean

      sig do
        params(
          hash: T::Hash[Symbol, Object],
          key: Symbol,
          default: T::Boolean
        ).returns(T::Boolean)
      end
      def self.boolean_with_default(hash, key, default)
        boolean_value(hash.fetch(key, default), key)
      end
      private_class_method :boolean_with_default

      sig { params(value: T.nilable(Object), key: Symbol).returns(T.nilable(T::Boolean)) }
      def self.optional_boolean(value, key)
        return if value.nil?

        boolean_value(value, key)
      end
      private_class_method :optional_boolean

      sig { params(value: Object, key: Symbol).returns(T::Boolean) }
      def self.boolean_value(value, key)
        return value if value == true || value == false

        raise TypeError, "#{key} must be a boolean"
      end
      private_class_method :boolean_value

      sig { params(value: T.nilable(Object), key: Symbol).returns(T.nilable(T::Array[String])) }
      def self.optional_string_array(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be an array of strings" unless value.is_a?(Array) && value.all?(String)

        value.map { |entry| T.cast(entry, String) }
      end
      private_class_method :optional_string_array

      sig { params(value: T.nilable(Object), key: Symbol).returns(T.nilable(T::Hash[String, Object])) }
      def self.optional_string_hash(value, key)
        return if value.nil?

        required_string_hash(value, key)
      end
      private_class_method :optional_string_hash

      sig { params(value: Object, key: Symbol).returns(T::Hash[String, Object]) }
      def self.required_string_hash(value, key)
        raise TypeError, "#{key} must be a hash" unless value.is_a?(Hash)

        result = T.let({}, T::Hash[String, Object])
        value.each do |raw_key, raw_value|
          parsed_key = T.cast(raw_key, Object)
          raise TypeError, "#{key} keys must be strings" unless parsed_key.is_a?(String)

          result[parsed_key] = T.cast(raw_value, Object)
        end
        result
      end
      private_class_method :required_string_hash

      sig { params(value: Object, key: Symbol).returns(T::Array[T::Hash[String, Object]]) }
      def self.strict_hash_array(value, key)
        raise TypeError, "#{key} must be an array" unless value.is_a?(Array)

        value.map { |entry| required_string_hash(T.cast(entry, Object), key) }
      end
      private_class_method :strict_hash_array

      sig { params(value: Object, key: Symbol).returns(T::Array[T::Hash[String, Object]]) }
      def self.tolerant_hash_array(value, key)
        raise TypeError, "#{key} must be an array" unless value.is_a?(Array)

        value.filter_map do |entry|
          parsed_entry = T.cast(entry, Object)
          required_string_hash(parsed_entry, key) if parsed_entry.is_a?(Hash)
        end
      end
      private_class_method :tolerant_hash_array

      sig { params(value: Object).returns(T::Array[Dependabot::Credential]) }
      def self.credentials(value)
        strict_hash_array(value, :credentials).map do |entry|
          Dependabot::Credential.new(credential_hash(entry))
        end
      end
      private_class_method :credentials

      sig do
        params(hash: T::Hash[String, Object])
          .returns(T::Hash[String, T.any(T::Boolean, String, T::Array[String])])
      end
      def self.credential_hash(hash)
        hash.to_h do |key, value|
          parsed_value =
            case value
            when String, TrueClass, FalseClass then value
            when Array
              raise TypeError, "credential array values must contain strings" unless value.all?(String)

              value.map { |entry| T.cast(entry, String) }
            else
              raise TypeError, "credential values must be strings, booleans, or string arrays"
            end

          [key, parsed_value]
        end
      end
      private_class_method :credential_hash
    end
  end
end
