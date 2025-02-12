# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/ecosystem"
require "dependabot/bun/requirement"
require "dependabot/bun/version_selector"
require "dependabot/bun/registry_helper"
require "dependabot/bun/npm_package_manager"
require "dependabot/bun/yarn_package_manager"
require "dependabot/bun/pnpm_package_manager"
require "dependabot/bun/bun_package_manager"
require "dependabot/bun/language"
require "dependabot/bun/constraint_helper"

module Dependabot
  module Bun
    ECOSYSTEM = "bun"
    MANIFEST_FILENAME = "package.json"
    LERNA_JSON_FILENAME = "lerna.json"
    PACKAGE_MANAGER_VERSION_REGEX = /
      ^                        # Start of string
      (?<major>\d+)            # Major version (required, numeric)
      \.                       # Separator between major and minor versions
      (?<minor>\d+)            # Minor version (required, numeric)
      \.                       # Separator between minor and patch versions
      (?<patch>\d+)            # Patch version (required, numeric)
      (                        # Start pre-release section
        -(?<pre_release>[a-zA-Z0-9.]+) # Pre-release label (optional, alphanumeric or dot-separated)
      )?
      (                        # Start build metadata section
        \+(?<build>[a-zA-Z0-9.]+) # Build metadata (optional, alphanumeric or dot-separated)
      )?
      $                        # End of string
    /x # Extended mode for readability

    VALID_REQUIREMENT_CONSTRAINT = /
      ^                        # Start of string
      (?<operator>=|>|>=|<|<=|~>|\\^) # Allowed operators
      \s*                      # Optional whitespace
      (?<major>\d+)            # Major version (required)
      (\.(?<minor>\d+))?       # Minor version (optional)
      (\.(?<patch>\d+))?       # Patch version (optional)
      (                        # Start pre-release section
        -(?<pre_release>[a-zA-Z0-9.]+) # Pre-release label (optional)
      )?
      (                        # Start build metadata section
        \+(?<build>[a-zA-Z0-9.]+) # Build metadata (optional)
      )?
      $                        # End of string
    /x # Extended mode for readability

    MANIFEST_PACKAGE_MANAGER_KEY = "packageManager"
    MANIFEST_ENGINES_KEY = "engines"

    # Error malformed version number string
    ERROR_MALFORMED_VERSION_NUMBER = "Malformed version number"

    class PackageManagerHelper
      extend T::Sig
      extend T::Helpers

      sig do
        params(
          package_json: T.nilable(T::Hash[String, T.untyped]),
          lockfiles: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)],
          registry_config_files: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)],
          credentials: T.nilable(T::Array[Dependabot::Credential])
        ).void
      end
      def initialize(package_json, lockfiles, registry_config_files, credentials)
        @package_json = package_json
        @lockfiles = lockfiles
        @registry_helper = T.let(
          RegistryHelper.new(registry_config_files, credentials),
          Dependabot::Bun::RegistryHelper
        )

        @manifest_package_manager = T.let(package_json&.fetch(MANIFEST_PACKAGE_MANAGER_KEY, nil), T.nilable(String))
        @engines = T.let(package_json&.fetch(MANIFEST_ENGINES_KEY, nil), T.nilable(T::Hash[String, T.untyped]))

        @installed_versions = T.let({}, T::Hash[String, String])
        @registries = T.let({}, T::Hash[String, String])

        @language = T.let(nil, T.nilable(Ecosystem::VersionManager))
        @language_requirement = T.let(nil, T.nilable(Requirement))
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        package_manager_by_name(ECOSYSTEM)
      end

      sig { returns(Ecosystem::VersionManager) }
      def language
        @language ||= Language.new(
          raw_version: Helpers.node_version,
          requirement: language_requirement
        )
      end

      sig { returns(T.nilable(Requirement)) }
      def language_requirement
        @language_requirement ||= find_engine_constraints_as_requirement(Language::NAME)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      sig { params(name: String).returns(T.nilable(Requirement)) }
      def find_engine_constraints_as_requirement(name)
        Dependabot.logger.info("Processing engine constraints for #{name}")

        return nil unless @engines.is_a?(Hash) && @engines[name]

        raw_constraint = @engines[name].to_s.strip
        return nil if raw_constraint.empty?

        if Dependabot::Experiments.enabled?(:enable_engine_version_detection)
          constraints = ConstraintHelper.extract_ruby_constraints(raw_constraint)
          # When constraints are invalid we return constraints array nil
          if constraints.nil?
            Dependabot.logger.warn(
              "Unrecognized constraint format for #{name}: #{raw_constraint}"
            )
          end
        else
          raw_constraints = raw_constraint.split
          constraints = raw_constraints.map do |constraint|
            case constraint
            when /^\d+$/
              ">=#{constraint}.0.0 <#{constraint.to_i + 1}.0.0"
            when /^\d+\.\d+$/
              ">=#{constraint} <#{constraint.split('.').first.to_i + 1}.0.0"
            when /^\d+\.\d+\.\d+$/
              "=#{constraint}"
            else
              Dependabot.logger.warn("Unrecognized constraint format for #{name}: #{constraint}")
              constraint
            end
          end

        end

        if constraints && !constraints.empty?
          Dependabot.logger.info("Parsed constraints for #{name}: #{constraints.join(', ')}")
          Requirement.new(constraints)
        end
      rescue StandardError => e
        Dependabot.logger.error("Error processing constraints for #{name}: #{e.message}")
        nil
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(name: String).returns(T.nilable(T.any(Integer, String))) }
      def setup(name)
        # we prioritize version mentioned in "packageManager" instead of "engines"
        # i.e. if { engines : "pnpm" : "6" } and { packageManager: "pnpm@6.0.2" },
        # we go for the specificity mentioned in packageManager (6.0.2)

        unless @manifest_package_manager&.start_with?("#{name}@") ||
               (@manifest_package_manager&.==name.to_s) ||
               @manifest_package_manager.nil?
          return
        end

        return package_manager.version.to_s if package_manager.deprecated? || package_manager.unsupported?

        if @engines && @manifest_package_manager.nil?
          # if "packageManager" doesn't exists in manifest file,
          # we check if we can extract "engines" information
          version = check_engine_version(name)

        elsif @manifest_package_manager&.==name.to_s
          # if "packageManager" is found but no version is specified (i.e. pnpm@1.2.3),
          # we check if we can get "engines" info to override default version
          version = check_engine_version(name) if @engines

        elsif @manifest_package_manager&.start_with?("#{name}@")
          # if "packageManager" info has version specification i.e. yarn@3.3.1
          # we go with the version in "packageManager"
          Dependabot.logger.info(
            "Found \"#{MANIFEST_PACKAGE_MANAGER_KEY}\" : \"#{@manifest_package_manager}\". " \
            "Skipped checking \"#{MANIFEST_ENGINES_KEY}\"."
          )
        end

        version ||= requested_version(name)

        if version
          raise_if_unsupported!(name, version.to_s)
        else
          version = guessed_version(name)

          raise_if_unsupported!(name, version.to_s) if version
        end
        version
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
      sig { params(name: String).returns(T.nilable(String)) }
      def detect_version(name)
        # Prioritize version mentioned in "packageManager" instead of "engines"
        if @manifest_package_manager&.start_with?("#{name}@")
          detected_version = @manifest_package_manager.split("@").last.to_s
        end

        # If "packageManager" has no version specified, check if we can extract "engines" information
        detected_version ||= check_engine_version(name) if detected_version.to_s.empty?

        # If neither "packageManager" nor "engines" have versions, infer version from lockfileVersion
        detected_version ||= guessed_version(name) if detected_version.to_s.empty?

        # Strip and validate version format
        detected_version_string = detected_version.to_s.strip

        # Ensure detected_version is neither "0" nor invalid format
        return if detected_version_string == "0" || !detected_version_string.match?(ConstraintHelper::VERSION_REGEX)

        detected_version_string
      end

      sig { params(name: String).returns(Ecosystem::VersionManager) }
      def package_manager_by_name(name)
        detected_version = detect_version(name)

        # if we have a detected version, we check if it is deprecated or unsupported
        if detected_version
          package_manager = BunPackageManager.new(
            detected_version: detected_version.to_s
          )
          return package_manager if package_manager.deprecated? || package_manager.unsupported?
        end

        BunPackageManager.new(
          detected_version: detected_version,
          raw_version: installed_version
        )
      end

      sig { returns(T.nilable(String)) }
      def installed_version
        Helpers.bun_version
      end

      private

      sig { params(name: String, version: String).void }
      def raise_if_unsupported!(name, version)
        return unless name == PNPMPackageManager::NAME
        return unless Version.new(version) < Version.new("7")

        raise ToolVersionNotSupported.new(PNPMPackageManager::NAME.upcase, version, "7.*, 8.*, 9.*")
      end

      sig { params(name: String).returns(T.nilable(String)) }
      def requested_version(name)
        return unless @manifest_package_manager

        match = @manifest_package_manager.match(/^#{name}@(?<version>\d+.\d+.\d+)/)
        return unless match

        Dependabot.logger.info("Requested version #{match['version']}")
        match["version"]
      end

      sig { params(name: String).returns(T.nilable(T.any(Integer, String))) }
      def guessed_version(name)
        lockfile = @lockfiles[name.to_sym]
        return unless lockfile

        version = Helpers.send(:"#{name}_version_numeric", lockfile)

        Dependabot.logger.info("Guessed version info \"#{name}\" : \"#{version}\"")

        version
      end

      sig { params(name: T.untyped).returns(T.nilable(String)) }
      def check_engine_version(name)
        return if @package_json.nil?

        version_selector = VersionSelector.new

        engine_versions = version_selector.setup(@package_json, name, BunPackageManager::SUPPORTED_VERSIONS)

        return if engine_versions.empty?

        version = engine_versions[name]
        Dependabot.logger.info("Returned (#{MANIFEST_ENGINES_KEY}) info \"#{name}\" : \"#{version}\"")
        version
      end
    end
  end
end
