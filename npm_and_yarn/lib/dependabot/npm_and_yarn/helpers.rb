# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module Helpers
      def self.npm_version(lockfile_content)
        "npm#{npm_version_numeric(lockfile_content)}"
      end

      def self.npm_version_numeric(lockfile_content)
        return 8 unless lockfile_content
        return 8 if JSON.parse(lockfile_content)["lockfileVersion"] >= 2

        6
      rescue JSON::ParserError
        6
      end

      def self.fetch_yarnrc_yml_value(key, default_value)
        if File.exist?(".yarnrc.yml") && (yarnrc = YAML.load_file(".yarnrc.yml"))
          yarnrc.fetch(key, default_value)
        else
          default_value
        end
      end

      def self.yarn_berry?(yarn_lock)
        yaml = YAML.safe_load(yarn_lock.content)
        yaml.key?("__metadata")
      rescue StandardError
        false
      end

      def self.yarn_major_version
        output = SharedHelpers.run_shell_command("yarn --version")
        Version.new(output).major
      end

      def self.yarn_zero_install?
        File.exist?(".pnp.cjs")
      end

      def self.yarn_offline_cache?
        yarn_cache_dir = fetch_yarnrc_yml_value("cacheFolder", ".yarn/cache")
        File.exist?(yarn_cache_dir) && (fetch_yarnrc_yml_value("nodeLinker", "") == "node-modules")
      end

      def self.yarn_berry_args
        if yarn_major_version == 2
          ""
        elsif yarn_major_version >= 3 && (yarn_zero_install? || yarn_offline_cache?)
          "--mode=skip-build"
        else
          # We only want this mode if the cache is not being updated/managed
          # as this improperly leaves old versions in the cache
          "--mode=update-lockfile"
        end
      end

      def self.setup_yarn_berry
        # Always disable immutable installs so yarn's CI detection doesn't prevent updates.
        SharedHelpers.run_shell_command("yarn config set enableImmutableInstalls false")
        # We never want to execute postinstall scripts, either set this config or mode=skip-build must be set
        if yarn_major_version == 2 || !yarn_zero_install?
          SharedHelpers.run_shell_command("yarn config set enableScripts false")
        end
        if (http_proxy = ENV.fetch("HTTP_PROXY", false))
          SharedHelpers.run_shell_command("yarn config set httpProxy #{http_proxy}")
        end
        if (https_proxy = ENV.fetch("HTTPS_PROXY", false))
          SharedHelpers.run_shell_command("yarn config set httpsProxy #{https_proxy}")
        end
        return unless (ca_file_path = ENV.fetch("NODE_EXTRA_CA_CERTS", false))

        if yarn_major_version >= 4
          SharedHelpers.run_shell_command("yarn config set httpsCaFilePath #{ca_file_path}")
        else
          SharedHelpers.run_shell_command("yarn config set caFilePath #{ca_file_path}")
        end
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        setup_yarn_berry
        commands.each { |cmd| SharedHelpers.run_shell_command(cmd) }
      end

      # Run a single yarn command returning stdout/stderr
      def self.run_yarn_command(command)
        setup_yarn_berry
        SharedHelpers.run_shell_command(command)
      end

      def self.dependencies_with_all_versions_metadata(dependency_set)
        working_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
        dependencies = []

        names = dependency_set.dependencies.map(&:name)
        names.each do |name|
          all_versions = dependency_set.all_versions_for_name(name)
          all_versions.each do |dep|
            metadata_versions = dep.metadata.fetch(:all_versions, [])
            if metadata_versions.any?
              metadata_versions.each { |a| working_set << a }
            else
              working_set << dep
            end
          end
          dependency = working_set.dependency_for_name(name)
          dependency.metadata[:all_versions] = working_set.all_versions_for_name(name)
          dependencies << dependency
        end

        dependencies
      end
    end
  end
end
