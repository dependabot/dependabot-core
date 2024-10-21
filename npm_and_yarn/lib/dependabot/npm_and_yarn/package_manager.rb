# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/version_selector"
require "dependabot/package_manager"

module Dependabot
  module NpmAndYarn
    ECOSYSTEM = "npm_and_yarn"

    class NpmPackageManager < PackageManagerBase
      extend T::Sig
      PACKAGE_MANAGER = "npm"
      # Keep versions in ascending order
      NPM_V6 = "6"
      NPM_V7 = "7"
      NPM_V8 = "8"
      NPM_V9 = "9"

      SUPPORTED_VERSIONS = T.let([
        Version.new(NPM_V6),
        Version.new(NPM_V7),
        Version.new(NPM_V8),
        Version.new(NPM_V9)
      ].freeze, T::Array[Dependabot::Version])

      # Currently, we don't support any deprecated versions of npm
      # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
      # Example for deprecation:
      # DEPRECATED_VERSIONS = T.let([Version.new(NPM_V6)].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          ECOSYSTEM,
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_VERSIONS,
          SUPPORTED_VERSIONS
        )
      end
    end

    class YarnPackageManager < PackageManagerBase
      extend T::Sig
      PACKAGE_MANAGER = "yarn"
      YARN_V1 = "1"
      YARN_V2 = "2"
      YARN_V3 = "3"
      # Keep versions in ascending order
      SUPPORTED_VERSIONS = T.let([
        Version.new(YARN_V1),
        Version.new(YARN_V2),
        Version.new(YARN_V3)
      ].freeze, T::Array[Dependabot::Version])

      # Currently, we don't support any deprecated versions of yarn
      # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
      # Example for deprecation:
      # DEPRECATED_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          ECOSYSTEM,
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_VERSIONS,
          SUPPORTED_VERSIONS
        )
      end
    end

    class PNPMPackageManager < PackageManagerBase
      extend T::Sig
      PACKAGE_MANAGER = "pnpm"
      PNPM_V7 = "7"
      PNPM_V8 = "8"
      PNPM_V9 = "9"
      # Keep versions in ascending order
      SUPPORTED_VERSIONS = T.let([
        Version.new(PNPM_V7),
        Version.new(PNPM_V8),
        Version.new(PNPM_V9)
      ].freeze, T::Array[Dependabot::Version])

      # Currently, we don't support any deprecated versions of pnpm
      # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
      # Example for deprecation:
      # DEPRECATED_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          ECOSYSTEM,
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_VERSIONS,
          SUPPORTED_VERSIONS
        )
      end
    end

    class PackageManager < PackageManagerBase
      extend T::Sig
      extend T::Helpers

      def initialize(package_json, lockfiles:)
        @package_json = package_json
        @lockfiles = lockfiles
        @package_manager_meta = package_json.fetch("packageManager", nil)
        @engines = package_json.fetch("engines", nil)

        package_manager_name = @package_manager_meta&.split("@")&.first
        package_manager_class = find_package_manager_class(package_manager_name)
        version = setup(package_manager_name)

        @package_manager = package_manager_class.new(version) if package_manager_class

        super(
          ECOSYSTEM,
          package_manager_name,
          Version.new(version),
          package_manager.deprecated_versions,
          package_manager.supported_versions
        )
      end

      sig { returns(DependencyFile) }
      attr_reader :package_json
      sig { returns(T::Hash[String, T.nilable(DependencyFile)]) }
      attr_reader :lockfiles
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      attr_reader :package_manager_meta
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      attr_reader :engines
      sig { returns(PackageManagerBase) }
      attr_reader :package_manager

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def setup(name)
        # we prioritize version mentioned in "packageManager" instead of "engines"
        # i.e. if { engines : "pnpm" : "6" } and { packageManager: "pnpm@6.0.2" },
        # we go for the specificity mentioned in packageManager (6.0.2)

        unless @package_manager_meta&.start_with?("#{name}@") || (@package_manager_meta&.==name.to_s) || @package_manager_meta.nil?
          return
        end

        if @engines && @package_manager_meta.nil?
          # if "packageManager" doesn't exists in manifest file,
          # we check if we can extract "engines" information
          version = check_engine_version(name)

        elsif @package_manager_meta&.==name.to_s
          # if "packageManager" is found but no version is specified (i.e. pnpm@1.2.3),
          # we check if we can get "engines" info to override default version
          version = check_engine_version(name) if @engines

        elsif @package_manager_meta&.start_with?("#{name}@")
          # if "packageManager" info has version specification i.e. yarn@3.3.1
          # we go with the version in "packageManager"
          Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\". Skipped checking \"engines\".")
        end

        version ||= requested_version(name)

        if version
          raise_if_unsupported!(name, version)

          install(name, version)
        else
          version = guessed_version(name)

          if version
            raise_if_unsupported!(name, version.to_s)

            install(name, version) if name == "pnpm"
          end
        end

        version
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      private

      def find_package_manager_class(name)
        case name
        when "npm"
          NpmPackageManager
        when "yarn"
          YarnPackageManager
        when "pnpm"
          PNPMPackageManager
        end
      end

      def raise_if_unsupported!(name, version)
        return unless name == "pnpm"
        return unless Version.new(version) < Version.new("7")

        raise ToolVersionNotSupported.new("PNPM", version, "7.*, 8.*")
      end

      def install(name, version)
        Dependabot.logger.info("Installing \"#{name}@#{version}\"")

        SharedHelpers.run_shell_command(
          "corepack install #{name}@#{version} --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only"
        )
      end

      def requested_version(name)
        return unless @package_manager_meta

        match = @package_manager_meta.match(/^#{name}@(?<version>\d+.\d+.\d+)/)
        return unless match

        Dependabot.logger.info("Requested version #{match['version']}")
        match["version"]
      end

      def guessed_version(name)
        lockfile = @lockfiles[name.to_sym]
        return unless lockfile

        version = Helpers.send(:"#{name}_version_numeric", lockfile)

        Dependabot.logger.info("Guessed version info \"#{name}\" : \"#{version}\"")

        version
      end

      sig { params(name: T.untyped).returns(T.nilable(String)) }
      def check_engine_version(name)
        version_selector = VersionSelector.new
        engine_versions = version_selector.setup(@package_json, name)

        return if engine_versions.empty?

        version = engine_versions[name]
        Dependabot.logger.info("Returned (engines) info \"#{name}\" : \"#{version}\"")
        version
      end
    end
  end
end
