# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    module Helpers
      extend T::Sig

      YARN_PATH_NOT_FOUND =
        /^.*(?<error>The "yarn-path" option has been set \(in [^)]+\), but the specified location doesn't exist)/

      # NPM Version Constants
      NPM_V10 = 10
      NPM_V8 = 8
      NPM_V6 = 6
      NPM_DEFAULT_VERSION = NPM_V8

      # PNPM Version Constants
      PNPM_V9 = 9
      PNPM_V8 = 8
      PNPM_V7 = 7
      PNPM_V6 = 6
      PNPM_DEFAULT_VERSION = PNPM_V9
      PNPM_FALLBACK_VERSION = PNPM_V6

      # YARN Version Constants
      YARN_V3 = 3
      YARN_V2 = 2
      YARN_V1 = 1
      YARN_DEFAULT_VERSION = YARN_V3
      YARN_FALLBACK_VERSION = YARN_V1

      # Determines the npm version depends to the feature flag
      # If the feature flag is enabled, we are going to use the minimum version npm 8
      # Otherwise, we are going to use old versionining npm 6
      sig { params(lockfile: T.nilable(DependencyFile)).returns(Integer) }
      def self.npm_version_numeric(lockfile)
        if Dependabot::Experiments.enabled?(:enable_corepack_for_npm_and_yarn)
          return npm_version_numeric_latest(lockfile)
        end

        fallback_version_npm8 = Dependabot::Experiments.enabled?(:npm_fallback_version_above_v6)

        return npm_version_numeric_npm8_or_higher(lockfile) if fallback_version_npm8

        npm_version_numeric_npm6_or_higher(lockfile)
      end

      sig { params(lockfile: T.nilable(DependencyFile)).returns(Integer) }
      def self.npm_version_numeric_npm6_or_higher(lockfile)
        lockfile_content = lockfile&.content

        if lockfile_content.nil? ||
           lockfile_content.strip.empty? ||
           JSON.parse(lockfile_content)["lockfileVersion"].to_i >= 2
          return NPM_V8
        end

        NPM_V6
      rescue JSON::ParserError
        NPM_V6
      end

      # Determines the npm version based on the lockfile version
      # - NPM 7 uses lockfileVersion 2
      # - NPM 8 uses lockfileVersion 2
      # - NPM 9 uses lockfileVersion 3
      sig { params(lockfile: T.nilable(DependencyFile)).returns(Integer) }
      def self.npm_version_numeric_npm8_or_higher(lockfile)
        lockfile_content = lockfile&.content

        # Return default NPM version if there's no lockfile or it's empty
        return NPM_DEFAULT_VERSION if lockfile_content.nil? || lockfile_content.strip.empty?

        parsed_lockfile = JSON.parse(lockfile_content)

        lockfile_version_str = parsed_lockfile["lockfileVersion"]

        # Default to npm default version if lockfileVersion is missing or empty
        return NPM_DEFAULT_VERSION if lockfile_version_str.nil? || lockfile_version_str.to_s.strip.empty?

        lockfile_version = lockfile_version_str.to_i

        # Using npm 8 as the default for lockfile_version > 2.
        # Update needed to support npm 9+ based on lockfile version.
        return NPM_V8 if lockfile_version >= 2

        NPM_DEFAULT_VERSION
      rescue JSON::ParserError
        NPM_DEFAULT_VERSION # Fallback to default npm version if parsing fails
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(lockfile: T.nilable(DependencyFile)).returns(Integer) }
      def self.npm_version_numeric_latest(lockfile)
        lockfile_content = lockfile&.content

        # Return npm 10 as the default if the lockfile is missing or empty
        return NPM_V10 if lockfile_content.nil? || lockfile_content.strip.empty?

        # Parse the lockfile content to extract the `lockfileVersion`
        parsed_lockfile = JSON.parse(lockfile_content)
        lockfile_version = parsed_lockfile["lockfileVersion"]&.to_i

        # Determine the appropriate npm version based on `lockfileVersion`
        if lockfile_version.nil?
          NPM_V10 # Use npm 10 if `lockfileVersion` is missing or nil
        elsif lockfile_version >= 3
          NPM_V10 # Use npm 10 for lockfileVersion 3 or higher
        elsif lockfile_version >= 2
          NPM_V8 # Use npm 8 for lockfileVersion 2
        elsif lockfile_version >= 1
          # Use npm 8 if the fallback version flag is enabled, otherwise use npm 6
          Dependabot::Experiments.enabled?(:npm_fallback_version_above_v6) ? NPM_V8 : NPM_V6
        else
          NPM_V10 # Default to npm 10 for unexpected or unsupported versions
        end
      rescue JSON::ParserError
        NPM_V8 # Fallback to npm 8 if the lockfile content cannot be parsed
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(yarn_lock: T.nilable(DependencyFile)).returns(Integer) }
      def self.yarn_version_numeric(yarn_lock)
        lockfile_content = yarn_lock&.content

        return YARN_DEFAULT_VERSION if lockfile_content.nil? || lockfile_content.strip.empty?

        if yarn_berry?(yarn_lock)
          YARN_DEFAULT_VERSION
        else
          YARN_FALLBACK_VERSION
        end
      end

      # Mapping from lockfile versions to PNPM versions is at
      # https://github.com/pnpm/spec/tree/274ff02de23376ad59773a9f25ecfedd03a41f64/lockfile, but simplify it for now.

      sig { params(pnpm_lock: T.nilable(DependencyFile)).returns(Integer) }
      def self.pnpm_version_numeric(pnpm_lock)
        lockfile_content = pnpm_lock&.content

        return PNPM_DEFAULT_VERSION if !lockfile_content || lockfile_content.strip.empty?

        pnpm_lockfile_version_str = pnpm_lockfile_version(pnpm_lock)

        return PNPM_FALLBACK_VERSION unless pnpm_lockfile_version_str

        pnpm_lockfile_version = pnpm_lockfile_version_str.to_f

        return PNPM_V9 if pnpm_lockfile_version >= 9.0
        return PNPM_V8 if pnpm_lockfile_version >= 6.0
        return PNPM_V7 if pnpm_lockfile_version >= 5.4

        PNPM_FALLBACK_VERSION
      end

      sig { params(key: String, default_value: String).returns(T.untyped) }
      def self.fetch_yarnrc_yml_value(key, default_value)
        if File.exist?(".yarnrc.yml") && (yarnrc = YAML.load_file(".yarnrc.yml"))
          yarnrc.fetch(key, default_value)
        else
          default_value
        end
      end

      sig { params(package_lock: T.nilable(DependencyFile)).returns(T::Boolean) }
      def self.npm8?(package_lock)
        return true unless package_lock&.content

        npm_version_numeric(package_lock) == NPM_V8
      end

      sig { params(yarn_lock: T.nilable(DependencyFile)).returns(T::Boolean) }
      def self.yarn_berry?(yarn_lock)
        return false if yarn_lock.nil? || yarn_lock.content.nil?

        yaml = YAML.safe_load(T.must(yarn_lock.content))
        yaml.key?("__metadata")
      rescue StandardError
        false
      end

      sig { returns(T.any(Integer, T.noreturn)) }
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

        handle_subprocess_failure(e)
      end

      sig { params(error: StandardError).returns(T.noreturn) }
      def self.handle_subprocess_failure(error)
        message = error.message
        if YARN_PATH_NOT_FOUND.match?(message)
          error = T.must(T.must(YARN_PATH_NOT_FOUND.match(message))[:error]).sub(Dir.pwd, ".")
          raise MisconfiguredTooling.new("Yarn", error)
        end

        if message.include?("Internal Error") && message.include?(".yarnrc.yml")
          raise MisconfiguredTooling.new("Invalid .yarnrc.yml file", message)
        end

        raise
      end

      sig { returns(T::Boolean) }
      def self.yarn_zero_install?
        File.exist?(".pnp.cjs")
      end

      sig { returns(T::Boolean) }
      def self.yarn_offline_cache?
        yarn_cache_dir = fetch_yarnrc_yml_value("cacheFolder", ".yarn/cache")
        File.exist?(yarn_cache_dir) && (fetch_yarnrc_yml_value("nodeLinker", "") == "node-modules")
      end

      sig { returns(String) }
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

      sig { returns(T::Boolean) }
      def self.yarn_berry_skip_build?
        yarn_major_version >= YARN_V3 && (yarn_zero_install? || yarn_offline_cache?)
      end

      sig { returns(T::Boolean) }
      def self.yarn_berry_disable_scripts?
        yarn_major_version == YARN_V2 || !yarn_zero_install?
      end

      sig { returns(T::Boolean) }
      def self.yarn_4_or_higher?
        yarn_major_version >= 4
      end

      sig { returns(T.nilable(String)) }
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
      sig { params(commands: T::Array[String]).void }
      def self.run_yarn_commands(*commands)
        setup_yarn_berry
        commands.each do |cmd, fingerprint|
          run_single_yarn_command(cmd, fingerprint: fingerprint) if cmd
        end
      end

      # Run single npm command returning stdout/stderr.
      #
      # NOTE: Needs to be explicitly run through corepack to respect the
      # `packageManager` setting in `package.json`, because corepack does not
      # add shims for NPM.
      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_npm_command(command, fingerprint: command)
        if Dependabot::Experiments.enabled?(:enable_corepack_for_npm_and_yarn)
          package_manager_run_command(NpmPackageManager::NAME, command, fingerprint: fingerprint)
        else
          Dependabot::SharedHelpers.run_shell_command(
            "corepack npm #{command}",
            fingerprint: "corepack npm #{fingerprint}"
          )
        end
      end

      # Setup yarn and run a single yarn command returning stdout/stderr
      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_yarn_command(command, fingerprint: nil)
        setup_yarn_berry
        run_single_yarn_command(command, fingerprint: fingerprint)
      end

      # Run single pnpm command returning stdout/stderr
      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_pnpm_command(command, fingerprint: nil)
        if Dependabot::Experiments.enabled?(:enable_corepack_for_npm_and_yarn)
          package_manager_run_command(PNPMPackageManager::NAME, command, fingerprint: fingerprint)
        else
          Dependabot::SharedHelpers.run_shell_command(
            "pnpm #{command}",
            fingerprint: "pnpm #{fingerprint || command}"
          )
        end
      end

      # Run single yarn command returning stdout/stderr
      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def self.run_single_yarn_command(command, fingerprint: nil)
        if Dependabot::Experiments.enabled?(:enable_corepack_for_npm_and_yarn)
          package_manager_run_command(YarnPackageManager::NAME, command, fingerprint: fingerprint)
        else
          Dependabot::SharedHelpers.run_shell_command(
            "yarn #{command}",
            fingerprint: "yarn #{fingerprint || command}"
          )
        end
      end

      # Install the package manager for specified version by using corepack
      # and prepare it for use by using corepack
      sig { params(name: String, version: String).returns(String) }
      def self.install(name, version)
        Dependabot.logger.info("Installing \"#{name}@#{version}\"")

        package_manager_install(name, version)
        package_manager_activate(name, version)
        installed_version = package_manager_version(name)

        Dependabot.logger.info("Installed version of #{name}: #{installed_version}")

        installed_version
      end

      # Install the package manager for specified version by using corepack
      sig { params(name: String, version: String).void }
      def self.package_manager_install(name, version)
        Dependabot::SharedHelpers.run_shell_command(
          "corepack install #{name}@#{version} --global --cache-only",
          fingerprint: "corepack install <name>@<version> --global --cache-only"
        ).strip
      end

      # Prepare the package manager for use by using corepack
      sig { params(name: String, version: String).void }
      def self.package_manager_activate(name, version)
        Dependabot::SharedHelpers.run_shell_command(
          "corepack prepare #{name}@#{version} --activate",
          fingerprint: "corepack prepare --activate"
        ).strip
      end

      # Get the version of the package manager by using corepack
      sig { params(name: String).returns(String) }
      def self.package_manager_version(name)
        package_manager_run_command(name, "-v")
      end

      # Run single command on package manager returning stdout/stderr
      sig do
        params(
          name: String,
          command: String,
          fingerprint: T.nilable(String)
        ).returns(String)
      end
      def self.package_manager_run_command(name, command, fingerprint: nil)
        Dependabot::SharedHelpers.run_shell_command(
          "corepack #{name} #{command}",
          fingerprint: "corepack #{name} #{fingerprint || command}"
        ).strip
      end
      private_class_method :run_single_yarn_command

      sig { params(pnpm_lock: DependencyFile).returns(T.nilable(String)) }
      def self.pnpm_lockfile_version(pnpm_lock)
        match = T.must(pnpm_lock.content).match(/^lockfileVersion: ['"]?(?<version>[\d.]+)/)
        return match[:version] if match

        nil
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).returns(T::Array[Dependency]) }
      def self.dependencies_with_all_versions_metadata(dependency_set)
        dependency_set.dependencies.map do |dependency|
          dependency.metadata[:all_versions] = dependency_set.all_versions_for_name(dependency.name)
          dependency
        end
      end
    end
  end
end
