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
      end

      def setup(name)
        # we prioritize version mentioned in "packageManager" instead of "engines"
        # i.e. if { engines : "pnpm" : "6" } and { packageManager: "pnpm@6.0.2" }
        # we go for the sepcificity mentioned in packageManager (6.0.2)

        # if (@package_manager&.include?("yarn"))
        #   @package_manager = "yarn" 
        # end


        if @package_manager.nil?
          version = check_engine_version(name)
        elsif @package_manager&.==name.to_s
          Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\"")
          version = check_engine_version(name)
        elsif @package_manager&.start_with?("#{name}@")
          Dependabot.logger.info("Found \"packageManager\" : \"#{@package_manager}\"")
        end

        version = requested_version(name) if version.nil?

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

        match["version"]
      end

      def guessed_version(name)
        lockfile = @lockfiles[name.to_sym]
        return unless lockfile

        Helpers.send(:"#{name}_version_numeric", lockfile)
      end

      def check_engine_version(name)
        Dependabot.logger.info("Fetching \"engines\" info")
        version_selector = VersionSelector.new()
        @engine_versions = version_selector.setup(@package_json, name)

        if @engine_versions.empty?
          Dependabot.logger.info("No relevant (engines) info for \"#{name}\"")
          return
        end

        version = @engine_versions[name]
        Dependabot.logger.info("Returned (engines) \"#{name}\" : \"#{version}\"")
        version
      end
    end
  end
end
