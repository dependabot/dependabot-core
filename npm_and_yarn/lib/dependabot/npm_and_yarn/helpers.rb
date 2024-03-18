# typed: true
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module Helpers
      YARN_PATH_NOT_FOUND =
        /^.*(?<error>The "yarn-path" option has been set \(in [^)]+\), but the specified location doesn't exist)/

      def self.npm_version_numeric(lockfile)
        lockfile_content = lockfile.content
        return 8 if JSON.parse(lockfile_content)["lockfileVersion"].to_i >= 2

        6
      rescue JSON::ParserError
        6
      end

      def self.yarn_version_numeric(yarn_lock)
        if yarn_berry?(yarn_lock)
          3
        else
          1
        end
      end

      # Mapping from lockfile versions to PNPM versions is at
      # https://github.com/pnpm/spec/tree/274ff02de23376ad59773a9f25ecfedd03a41f64/lockfile, but simplify it for now.
      def self.pnpm_version_numeric(pnpm_lock)
        if pnpm_lockfile_version(pnpm_lock).to_f >= 6.0
          8
        elsif pnpm_lockfile_version(pnpm_lock).to_f >= 5.4
          7
        else
          6
        end
      end

      def self.fetch_yarnrc_yml_value(key, default_value)
        if File.exist?(".yarnrc.yml") && (yarnrc = YAML.load_file(".yarnrc.yml"))
          yarnrc.fetch(key, default_value)
        else
          default_value
        end
      end

      def self.npm8?(package_lock)
        return true unless package_lock

        npm_version_numeric(package_lock) == 8
      end

      def self.yarn_berry?(yarn_lock)
        yaml = YAML.safe_load(yarn_lock.content)
        yaml.key?("__metadata")
      rescue StandardError
        false
      end

      def self.yarn_major_version
        retries = 0
        output = run_single_yarn_command("--version")
        Version.new(output).major
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        # Should never happen, can probably be removed once this settles
        raise "Failed to replace ENV, not sure why" if T.must(retries).positive?

        message = e.message

        missing_env_var_regex = %r{Environment variable not found \((?:[^)]+)\) in #{Dir.pwd}/(?<path>\S+)}

        if message.match?(missing_env_var_regex)
          match = T.must(message.match(missing_env_var_regex))
          path = T.must(match.named_captures["path"])

          File.write(path, File.read(path).gsub(/\$\{[^}-]+\}/, ""))
          retries = T.must(retries) + 1

          retry
        end

        if YARN_PATH_NOT_FOUND.match?(message)
          error = T.must(T.must(YARN_PATH_NOT_FOUND.match(message))[:error]).sub(Dir.pwd, ".")
          raise MisconfiguredTooling.new("Yarn", error)
        end

        if e.message.include?("Internal Error") && e.message.include?(".yarnrc.yml")
          raise MisconfiguredTooling.new("Invalid .yarnrc.yml file", e.message)
        end

        raise
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
        elsif yarn_berry_skip_build?
          "--mode=skip-build"
        else
          # We only want this mode if the cache is not being updated/managed
          # as this improperly leaves old versions in the cache
          "--mode=update-lockfile"
        end
      end

      def self.yarn_berry_skip_build?
        yarn_major_version >= 3 && (yarn_zero_install? || yarn_offline_cache?)
      end

      def self.yarn_berry_disable_scripts?
        yarn_major_version == 2 || !yarn_zero_install?
      end

      def self.yarn_4_or_higher?
        yarn_major_version >= 4
      end

      def self.setup_yarn_berry
        # Always disable immutable installs so yarn's CI detection doesn't prevent updates.
        run_single_yarn_command("config set enableImmutableInstalls false")
        # Do not generate a cache if offline cache disabled. Otherwise side effects may confuse further checks
        run_single_yarn_command("config set enableGlobalCache true") unless yarn_berry_skip_build?
        # We never want to execute postinstall scripts, either set this config or mode=skip-build must be set
        run_single_yarn_command("config set enableScripts false") if yarn_berry_disable_scripts?
        if (http_proxy = ENV.fetch("HTTP_PROXY", false))
          run_single_yarn_command("config set httpProxy #{http_proxy}", fingerprint: "config set httpProxy <proxy>")
        end
        if (https_proxy = ENV.fetch("HTTPS_PROXY", false))
          run_single_yarn_command("config set httpsProxy #{https_proxy}", fingerprint: "config set httpsProxy <proxy>")
        end
        return unless (ca_file_path = ENV.fetch("NODE_EXTRA_CA_CERTS", false))

        if yarn_4_or_higher?
          run_single_yarn_command("config set httpsCaFilePath #{ca_file_path}")
        else
          run_single_yarn_command("config set caFilePath #{ca_file_path}")
        end
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        setup_yarn_berry
        commands.each { |cmd, fingerprint| run_single_yarn_command(cmd, fingerprint: fingerprint) }
      end

      # Run single npm command returning stdout/stderr.
      #
      # NOTE: Needs to be explicitly run through corepack to respect the
      # `packageManager` setting in `package.json`, because corepack does not
      # add shims for NPM.
      def self.run_npm_command(command, fingerprint: command)
        SharedHelpers.run_shell_command("corepack npm #{command}", fingerprint: "corepack npm #{fingerprint}")
      end

      # Setup yarn and run a single yarn command returning stdout/stderr
      def self.run_yarn_command(command, fingerprint: nil)
        setup_yarn_berry
        run_single_yarn_command(command, fingerprint: fingerprint)
      end

      # Run single pnpm command returning stdout/stderr
      def self.run_pnpm_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command("pnpm #{command}", fingerprint: "pnpm #{fingerprint || command}")
      end

      # Run single yarn command returning stdout/stderr
      def self.run_single_yarn_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command("yarn #{command}", fingerprint: "yarn #{fingerprint || command}")
      end
      private_class_method :run_single_yarn_command

      def self.pnpm_lockfile_version(pnpm_lock)
        pnpm_lock.content.match(/^lockfileVersion: ['"]?(?<version>[\d.]+)/)[:version]
      end

      def self.dependencies_with_all_versions_metadata(dependency_set)
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
