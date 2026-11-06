# typed: strict
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/uv/file_updater/lock_file_error_handler"

module Dependabot
  module Uv
    # The uv executable to run in the current directory.
    #
    # A project can pin uv with `required-version` (in `[tool.uv]` of pyproject.toml, or in uv.toml),
    # and uv refuses to run when its own version does not satisfy the pin. When the pin rejects the
    # bundled uv, the newest uv release on PyPI that satisfies it is installed and run instead. The pin
    # is read from the bundled uv's own error, so uv's config discovery and precedence rules apply.
    class UvExecutable
      extend T::Sig

      BUNDLED_COMMAND = "pyenv exec uv"
      INSTALL_ROOT = T.let(File.join(Dir.tmpdir, "dependabot-uv"), String)

      # Shell prefix for uv commands, e.g. "pyenv exec uv" in `"#{command} lock"`.
      sig { returns(String) }
      attr_reader :command

      # Environment the command needs; merge it into the env of every command run with it.
      sig { returns(T::Hash[String, String]) }
      attr_reader :env

      # Call from the directory uv will run in, after `pyenv local`: both decide which uv runs.
      sig { returns(UvExecutable) }
      def self.resolve
        mismatch = required_version_mismatch
        return new(command: BUNDLED_COMMAND, env: {}) unless mismatch

        required, running = mismatch
        Dependabot.logger.info("Project requires uv #{required}; installing it in place of the bundled uv #{running}")
        executable = install(required: required, running: running)

        # `pyenv exec` puts the active Python's bin directory first on PATH, which is where uv finds the
        # interpreter. The installed uv lives outside pyenv, so it gets the same PATH explicitly.
        python_bin = File.join(SharedHelpers.run_shell_command("pyenv prefix").strip, "bin")
        new(command: executable, env: { "PATH" => "#{python_bin}:#{ENV.fetch('PATH', '')}" })
      end

      sig { params(command: String, env: T::Hash[String, String]).void }
      def initialize(command:, env:)
        @command = command
        @env = env
      end

      # [required, running] when the project's `required-version` rejects the bundled uv; nil otherwise.
      # `uv cache dir` is a local no-op that still loads the project's settings and enforces the pin.
      sig { returns(T.nilable([String, String])) }
      def self.required_version_mismatch
        SharedHelpers.run_shell_command("#{BUNDLED_COMMAND} cache dir", fingerprint: "#{BUNDLED_COMMAND} cache dir")
        nil
      rescue SharedHelpers::HelperSubprocessFailed => e
        # Any other failure resurfaces from the real command, where it is handled.
        match = e.message.match(FileUpdater::LockFileErrorHandler::UV_REQUIRED_VERSION_REGEX)
        return nil unless match

        [T.must(match[:required]), T.must(match[:running])]
      end
      private_class_method :required_version_mismatch

      # Installs once per requirement and job; later calls reuse the binary.
      sig { params(required: String, running: String).returns(String) }
      def self.install(required:, running:)
        target = File.join(INSTALL_ROOT, Digest::SHA256.hexdigest(required)[0, 16])
        executable = File.join(target, "bin", "uv")
        return executable if File.executable?(executable)

        # A failed earlier attempt can leave a partial target behind, which pip would not overwrite.
        FileUtils.rm_rf(target)
        SharedHelpers.run_shell_command(
          [
            "pyenv", "exec", "pip", "install", "--disable-pip-version-check", "--no-deps",
            "--only-binary", ":all:", "--target", target, "uv#{required}"
          ],
          fingerprint: "pyenv exec pip install --disable-pip-version-check --no-deps " \
                       "--only-binary :all: --target <target> uv<required_version>"
        )
        executable
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.error("Failed to install uv #{required}: #{e.message}")
        raise Dependabot::ToolVersionNotSupported.new("uv", required, running)
      end
      private_class_method :install
    end
  end
end
