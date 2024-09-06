# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/version_selector"

module Dependabot
  module NpmAndYarn
    class PackageManager
      def initialize(package_json, lockfiles:)
        @package_json = package_json
        @lockfiles = lockfiles
        @package_manager = package_json.fetch("packageManager", nil)
        @engines = package_json.fetch("engines", nil)
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def setup(name)
        # we prioritize version mentioned in "packageManager" instead of "engines"
        # i.e. if { engines : "pnpm" : "6" } and { packageManager: "pnpm@6.0.2" },
        # we go for the specificity mentioned in packageManager (6.0.2)
        # Dependabot::Experiments.register(:enable_pnpm_yarn_dynamic_engine, true)
        if Dependabot::Experiments.enabled?("enable_pnpm_yarn_dynamic_engine")

          unless @package_manager&.start_with?("#{name}@") || @package_manager == name.to_s || @package_manager.nil?
            return
          end

          if @engines && @package_manager.nil?
            # if "packageManager" doesn't exists in manifest file,
            # we check if we can extract "engines" information
            Dependabot.logger.info("No \"packageManager\" info found for \"#{name}\"")
            version = check_engine_version(name)

          elsif @package_manager&.==name.to_s
            # if "packageManager" is found but no version is specified (i.e. pnpm@1.2.3),
            # we check if we can get "engines" info to override default version
            Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\"")
            version = check_engine_version(name) if @engines

          elsif @package_manager&.start_with?("#{name}@")
            # if "packageManager" info has version specification i.e. yarn@3.3.1
            # we go with the version in "packageManager"
            Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\". Skipped checking \"engines\".")
          end
        else
          return unless @package_manager.nil? || @package_manager.start_with?("#{name}@")
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
        return unless @package_manager

        match = @package_manager.match(/^#{name}@(?<version>\d+.\d+.\d+)/)
        return unless match

        Dependabot.logger.info("Requested version #{match['version']}")
        match["version"]
      end

      def guessed_version(name)
        lockfile = @lockfiles[name.to_sym]
        return unless lockfile

        Dependabot.logger.info("Estimating version")
        Helpers.send(:"#{name}_version_numeric", lockfile)
      end

      def check_engine_version(name)
        version_selector = VersionSelector.new
        engine_versions = version_selector.setup(@package_json, name)

        if engine_versions.empty?
          Dependabot.logger.info("No relevant (engines) info for \"#{name}\"")
          return
        end

        version = engine_versions[name]
        Dependabot.logger.info("Returned (engines) info \"#{name}\" : \"#{version}\"")
        version
      end
    end
  end
end
