# typed: strong
# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "tempfile"
require "dependabot/credential"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/utils"
require "dependabot/uv/authed_url_builder"
require "dependabot/uv/file_updater/lock_file_error_handler"

module Dependabot
  module Uv
    # The uv executable to run in the current directory.
    #
    # A project can pin uv with `required-version` (in `[tool.uv]` of pyproject.toml, or in uv.toml),
    # and uv refuses to run when its own version does not satisfy the pin. When the pin rejects the
    # bundled uv, the newest uv release that satisfies it is installed and run instead. The pin is read
    # from the bundled uv's own error, so uv's config discovery and precedence rules apply.
    class UvExecutable
      extend T::Sig

      BUNDLED_COMMAND = "pyenv exec uv"
      INSTALLED_FINGERPRINT = "<uv_executable>"
      # Owned by this process, so nothing else can plant a binary there and nothing outlives the job.
      INSTALL_ROOT = T.let(File.join(Utils::BUMP_TMP_DIR_PATH, "uv"), String)
      # uv reads `required-version` from these files in the working directory or an ancestor. Dependabot
      # images ship no user- or system-level uv config.
      CONFIG_FILES = %w(uv.toml pyproject.toml).freeze

      # Shell prefix for uv commands, e.g. "pyenv exec uv" in `"#{command} lock"`.
      sig { returns(String) }
      attr_reader :command

      # Stands in for `command` in error fingerprints, which must not vary with the install path.
      sig { returns(String) }
      attr_reader :fingerprint

      # Environment the command needs; merge it into the env of every command run with it.
      sig { returns(T::Hash[String, String]) }
      attr_reader :env

      # Call from the directory uv will run in, after `pyenv local`: both decide which uv runs.
      sig { params(credentials: T::Array[Dependabot::Credential]).returns(UvExecutable) }
      def self.resolve(credentials:)
        mismatch = required_version_mismatch
        return new(command: BUNDLED_COMMAND, fingerprint: BUNDLED_COMMAND, env: {}) unless mismatch

        required, running = mismatch
        executable = install(required: required, running: running, credentials: credentials)

        # `pyenv exec` puts the active Python's bin directory first on PATH, which is where uv finds the
        # interpreter. The installed uv lives outside pyenv, so it gets the same PATH explicitly.
        python_bin = File.join(SharedHelpers.run_shell_command("pyenv prefix").strip, "bin")
        path = [python_bin, ENV.fetch("PATH", "")].reject(&:empty?).join(File::PATH_SEPARATOR)
        new(command: executable, fingerprint: INSTALLED_FINGERPRINT, env: { "PATH" => path })
      end

      sig { params(command: String, fingerprint: String, env: T::Hash[String, String]).void }
      def initialize(command:, fingerprint:, env:)
        @command = command
        @fingerprint = fingerprint
        @env = env
      end

      # [required, running] when the project's `required-version` rejects the bundled uv; nil otherwise.
      # `uv cache dir` is a local no-op that still loads the project's settings and enforces the pin.
      sig { returns(T.nilable([String, String])) }
      def self.required_version_mismatch
        # The probe costs a `pyenv exec` per uv command, so projects that cannot have a pin skip it.
        return nil unless pin_declared?

        SharedHelpers.run_shell_command("#{BUNDLED_COMMAND} cache dir", fingerprint: "#{BUNDLED_COMMAND} cache dir")
        nil
      rescue SharedHelpers::HelperSubprocessFailed => e
        # Any other failure resurfaces from the real command, where it is handled.
        match = e.message.match(FileUpdater::LockFileErrorHandler::UV_REQUIRED_VERSION_REGEX)
        return nil unless match

        [T.must(match[:required]), T.must(match[:running])]
      end
      private_class_method :required_version_mismatch

      # A text match only: uv still decides which file applies and what the pin means.
      sig { returns(T::Boolean) }
      def self.pin_declared?
        Pathname.pwd.ascend.any? do |dir|
          CONFIG_FILES.any? do |name|
            file = dir.join(name)
            file.file? && file.read.include?("required-version")
          end
        end
      end
      private_class_method :pin_declared?

      # Installs once per requirement and job; later calls reuse the binary.
      sig do
        params(required: String, running: String, credentials: T::Array[Dependabot::Credential]).returns(String)
      end
      def self.install(required:, running:, credentials:)
        target = File.join(INSTALL_ROOT, Digest::SHA256.hexdigest(required)[0, 16])
        executable = File.join(target, "bin", "uv")
        return executable if File.executable?(executable)

        Dependabot.logger.info("Project requires uv #{required}; installing it in place of the bundled uv #{running}")
        # A failed earlier attempt can leave a partial target behind, which pip would not overwrite.
        FileUtils.rm_rf(target)
        with_index_config(credentials) do |env|
          SharedHelpers.run_shell_command(
            [
              "pyenv", "exec", "pip", "install", "--disable-pip-version-check", "--no-deps",
              "--only-binary", ":all:", "--target", target, "uv#{required}"
            ],
            env: env,
            fingerprint: "pyenv exec pip install --disable-pip-version-check --no-deps " \
                         "--only-binary :all: --target <target> uv<required_version>"
          )
        end
        executable
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise Dependabot::OutOfDisk if e.message.include?("[Errno 28] No space left on device")
        raise Dependabot::OutOfMemory if e.message.include?("MemoryError")

        Dependabot.logger.error("Failed to install uv #{required}: #{e.message}")
        raise Dependabot::ToolVersionNotSupported.new(
          "uv", required, "#{running} (bundled), or any uv release available from the Python package index"
        )
      end
      private_class_method :install

      # Jobs whose index replaces PyPI may have no route to PyPI, so uv comes from that index too. The
      # authenticated URLs go in a 0600 pip config file: command arguments are logged verbatim, and env
      # values are only redacted for TOKEN keys.
      sig do
        params(
          credentials: T::Array[Dependabot::Credential],
          block: T.proc.params(env: T::Hash[String, String]).void
        ).void
      end
      def self.with_index_config(credentials, &block)
        base_url, *extra_urls = credentials
                                .select { |cred| cred["type"] == "python_index" && cred.replaces_base? }
                                .map { |cred| AuthedUrlBuilder.authed_url(credential: cred) }
        return yield({}) unless base_url

        Tempfile.create(["dependabot-uv-pip", ".conf"]) do |config|
          config.write("[global]\nindex-url = #{base_url}\n")
          config.write("extra-index-url =\n#{extra_urls.map { |url| "    #{url}\n" }.join}") if extra_urls.any?
          config.flush
          yield({ "PIP_CONFIG_FILE" => config.path })
        end
      end
      private_class_method :with_index_config
    end
  end
end
