# typed: strict
# frozen_string_literal: true

require "digest"
require "English"
require "excon"
require "fileutils"
require "json"
require "open3"
require "sorbet-runtime"
require "tmpdir"

require "dependabot/credential"
require "dependabot/simple_instrumentor"
require "dependabot/utils"
require "dependabot/errors"
require "dependabot/workspace"
require "dependabot"
require "dependabot/command_helpers"

module Dependabot
  module SharedHelpers # rubocop:disable Metrics/ModuleLength
    extend T::Sig

    GIT_CONFIG_GLOBAL_PATH = T.let(File.expand_path(".gitconfig", Utils::BUMP_TMP_DIR_PATH), String)
    USER_AGENT = T.let(
      "dependabot-core/#{Dependabot::VERSION} " \
      "#{Excon::USER_AGENT} ruby/#{RUBY_VERSION} " \
      "(#{RUBY_PLATFORM}) " \
      "(+https://github.com/dependabot/dependabot-core)".freeze,
      String
    )
    SIGKILL = 9

    sig do
      type_parameters(:T)
        .params(
          directory: String,
          repo_contents_path: T.nilable(String),
          block: T.proc.params(arg0: T.any(Pathname, String)).returns(T.type_parameter(:T))
        )
        .returns(T.type_parameter(:T))
    end
    def self.in_a_temporary_repo_directory(directory = "/", repo_contents_path = nil, &block)
      if repo_contents_path
        # If a workspace has been defined to allow orcestration of the git repo
        # by the runtime we should defer to it, otherwise we prepare the folder
        # for direct use and yield.
        if Dependabot::Workspace.active_workspace
          T.must(Dependabot::Workspace.active_workspace).change(&block)
        else
          path = Pathname.new(File.join(repo_contents_path, directory)).expand_path
          reset_git_repo(repo_contents_path)
          # Handle missing directories by creating an empty one and relying on the
          # file fetcher to raise a DependencyFileNotFound error
          FileUtils.mkdir_p(path)

          Dir.chdir(path) { yield(path) }
        end
      else
        in_a_temporary_directory(directory, &block)
      end
    end

    sig do
      type_parameters(:T)
        .params(
          directory: String,
          _block: T.proc.params(arg0: T.any(Pathname, String)).returns(T.type_parameter(:T))
        )
        .returns(T.type_parameter(:T))
    end
    def self.in_a_temporary_directory(directory = "/", &_block)
      FileUtils.mkdir_p(Utils::BUMP_TMP_DIR_PATH)
      tmp_dir = Dir.mktmpdir(Utils::BUMP_TMP_FILE_PREFIX, Utils::BUMP_TMP_DIR_PATH)
      path = Pathname.new(File.join(tmp_dir, directory)).expand_path

      begin
        path = Pathname.new(File.join(tmp_dir, directory)).expand_path
        FileUtils.mkpath(path)
        Dir.chdir(path) { yield(path) }
      ensure
        FileUtils.rm_rf(tmp_dir)
      end
    end

    class HelperSubprocessFailed < Dependabot::DependabotError
      extend T::Sig

      sig { returns(String) }
      attr_reader :error_class

      sig { returns(T::Hash[Symbol, String]) }
      attr_reader :error_context

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :trace

      sig do
        params(
          message: String,
          error_context: T::Hash[Symbol, String],
          error_class: T.nilable(String),
          trace: T.nilable(T::Array[String])
        ).void
      end
      def initialize(message:, error_context:, error_class: nil, trace: nil)
        super(message)
        @error_class = T.let(error_class || "HelperSubprocessFailed", String)
        @error_context = error_context
        @fingerprint = T.let(error_context[:fingerprint] || error_context[:command], T.nilable(String))
        @trace = trace
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def sentry_context
        { fingerprint: [@fingerprint], extra: @error_context.except(:stderr_output, :fingerprint) }
      end
    end

    # Escapes all special characters, e.g. = & | <>
    sig { params(command: String).returns(String) }
    def self.escape_command(command)
      CommandHelpers.escape_command(command)
    end

    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/AbcSize
    sig do
      params(
        command: String,
        function: String,
        args: T.any(T::Array[T.any(String, T::Array[T::Hash[String, T.untyped]])], T::Hash[Symbol, String]),
        env: T.nilable(T::Hash[String, String]),
        stderr_to_stdout: T::Boolean,
        allow_unsafe_shell_command: T::Boolean,
        error_class: T.class_of(HelperSubprocessFailed),
        command_type: Symbol,
        timeout: Integer
      )
        .returns(T.nilable(T.any(String, T::Hash[String, T.untyped], T::Array[T::Hash[String, T.untyped]])))
    end
    def self.run_helper_subprocess(command:, function:, args:, env: nil,
                                   stderr_to_stdout: false,
                                   allow_unsafe_shell_command: false,
                                   error_class: HelperSubprocessFailed,
                                   command_type: :network,
                                   timeout: -1)
      start = Time.now
      stdin_data = JSON.dump(function: function, args: args)
      cmd = allow_unsafe_shell_command ? command : escape_command(command)

      # NOTE: For debugging native helpers in specs and dry-run: outputs the
      # bash command to run in the tmp directory created by
      # in_a_temporary_directory
      if ENV["DEBUG_FUNCTION"] == function
        puts helper_subprocess_bash_command(stdin_data: stdin_data, command: cmd, env: env)
        # Pause execution so we can run helpers inside the temporary directory
        T.unsafe(self).debugger
      end

      env_cmd = [env, cmd].compact
      if Experiments.enabled?(:enable_shared_helpers_command_timeout)
        stdout, stderr, process = CommandHelpers.capture3_with_timeout(
          env_cmd,
          stdin_data: stdin_data,
          command_type: command_type,
          timeout: timeout
        )
      else
        stdout, stderr, process = T.unsafe(Open3).capture3(*env_cmd, stdin_data: stdin_data)
      end
      time_taken = Time.now - start

      if ENV["DEBUG_HELPERS"] == "true"
        puts env_cmd
        puts function
        puts stdout
        puts stderr
      end

      # Some package managers output useful stuff to stderr instead of stdout so
      # we want to parse this, most package manager will output garbage here so
      # would mess up json response from stdout
      stdout = "#{stderr}\n#{stdout}" if stderr_to_stdout

      error_context = {
        command: command,
        function: function,
        args: args,
        time_taken: time_taken,
        stderr_output: stderr[0..50_000], # Truncate to ~100kb
        process_exit_value: process.to_s,
        process_termsig: process&.termsig
      }

      check_out_of_memory_error(stderr, error_context, error_class)

      begin
        response = JSON.parse(stdout)
        return response["result"] if process&.success?

        raise error_class.new(
          message: response["error"],
          error_class: response["error_class"],
          error_context: error_context,
          trace: response["trace"]
        )
      rescue JSON::ParserError
        raise handle_json_parse_error(stdout, stderr, error_context, error_class)
      end
    end

    sig do
      params(stdout: String, stderr: String, error_context: T::Hash[Symbol, T.untyped],
             error_class: T.class_of(HelperSubprocessFailed))
        .returns(HelperSubprocessFailed)
    end
    def self.handle_json_parse_error(stdout, stderr, error_context, error_class)
      # If the JSON is invalid, the helper has likely failed
      # We should raise a more helpful error message
      message = if !stdout.strip.empty?
                  stdout
                elsif !stderr.strip.empty?
                  stderr
                else
                  "No output from command"
                end
      error_class.new(
        message: message,
        error_class: "JSON::ParserError",
        error_context: error_context
      )
    end

    # rubocop:enable Metrics/MethodLength
    sig do
      params(stderr: T.nilable(String), error_context: T::Hash[Symbol, String],
             error_class: T.class_of(HelperSubprocessFailed)).void
    end
    def self.check_out_of_memory_error(stderr, error_context, error_class)
      return unless stderr&.include?("JavaScript heap out of memory")

      raise error_class.new(
        message: "JavaScript heap out of memory",
        error_class: "Dependabot::OutOfMemoryError",
        error_context: error_context
      )
    end

    sig { returns(T::Array[T.class_of(Excon::Middleware::Base)]) }
    def self.excon_middleware
      T.must(T.cast(Excon.defaults, T::Hash[Symbol, T::Array[T.class_of(Excon::Middleware::Base)]])[:middlewares]) +
        [Excon::Middleware::Decompress] +
        [Excon::Middleware::RedirectFollower]
    end

    sig { params(headers: T.nilable(T::Hash[String, String])).returns(T::Hash[String, String]) }
    def self.excon_headers(headers = nil)
      headers ||= {}
      {
        "User-Agent" => USER_AGENT
      }.merge(headers)
    end

    sig { params(options: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
    def self.excon_defaults(options = nil)
      options ||= {}
      headers = T.cast(options.delete(:headers), T.nilable(T::Hash[String, String]))
      {
        instrumentor: Dependabot::SimpleInstrumentor,
        connect_timeout: 5,
        write_timeout: 5,
        read_timeout: 20,
        retry_limit: 4, # Excon defaults to four retries, but let's set it explicitly for clarity
        omit_default_port: true,
        middlewares: excon_middleware,
        headers: excon_headers(headers)
      }.merge(options)
    end

    sig do
      type_parameters(:T)
        .params(
          credentials: T::Array[Dependabot::Credential],
          _block: T.proc.returns(T.type_parameter(:T))
        )
        .returns(T.type_parameter(:T))
    end
    def self.with_git_configured(credentials:, &_block)
      safe_directories = find_safe_directories

      FileUtils.mkdir_p(Utils::BUMP_TMP_DIR_PATH)

      previous_config = ENV.fetch("GIT_CONFIG_GLOBAL", nil)
      previous_terminal_prompt = ENV.fetch("GIT_TERMINAL_PROMPT", nil)

      begin
        ENV["GIT_CONFIG_GLOBAL"] = GIT_CONFIG_GLOBAL_PATH
        ENV["GIT_TERMINAL_PROMPT"] = "false"
        configure_git_to_use_https_with_credentials(credentials, safe_directories)
        yield
      ensure
        ENV["GIT_CONFIG_GLOBAL"] = previous_config
        ENV["GIT_TERMINAL_PROMPT"] = previous_terminal_prompt
      end
    rescue Errno::ENOSPC => e
      raise Dependabot::OutOfDisk, e.message
    ensure
      FileUtils.rm_f(GIT_CONFIG_GLOBAL_PATH)
    end

    # Handle SCP-style git URIs
    sig { params(uri: String).returns(String) }
    def self.scp_to_standard(uri)
      return uri unless uri.start_with?("git@")

      "https://#{T.must(uri.split('git@').last).sub(%r{:/?}, '/')}"
    end

    sig { returns(String) }
    def self.credential_helper_path
      File.join(__dir__, "../../bin/git-credential-store-immutable")
    end

    # rubocop:disable Metrics/PerceivedComplexity
    sig { params(credentials: T::Array[Dependabot::Credential], safe_directories: T::Array[String]).void }
    def self.configure_git_to_use_https_with_credentials(credentials, safe_directories)
      File.open(GIT_CONFIG_GLOBAL_PATH, "w") do |file|
        file << "# Generated by dependabot/dependabot-core"
      end

      # Then add a file-based credential store that loads a file in this repo.
      # Under the hood this uses git credential-store, but it's invoked through
      # a wrapper binary that only allows non-mutating commands. Without this,
      # whenever the credentials are deemed to be invalid, they're erased.
      run_shell_command(
        "git config --global credential.helper " \
        "'!#{credential_helper_path} --file #{Dir.pwd}/git.store'",
        allow_unsafe_shell_command: true,
        fingerprint: "git config --global credential.helper '<helper_command>'"
      )

      # see https://github.blog/2022-04-12-git-security-vulnerability-announced/
      safe_directories.each do |path|
        run_shell_command("git config --global --add safe.directory #{path}")
      end

      github_credentials = credentials
                           .select { |c| c["type"] == "git_source" }
                           .select { |c| c["host"] == "github.com" }
                           .select { |c| c["password"] && c["username"] }

      # If multiple credentials are specified for github.com, pick the one that
      # *isn't* just an app token (since it must have been added deliberately)
      github_credential =
        github_credentials.find { |c| !c["password"]&.start_with?("v1.") } ||
        github_credentials.first

      # Make sure we always have https alternatives for github.com.
      configure_git_to_use_https("github.com") if github_credential.nil?

      deduped_credentials = credentials -
                            github_credentials +
                            [github_credential].compact

      # Build the content for our credentials file
      git_store_content = ""
      deduped_credentials.each do |cred|
        next unless cred["type"] == "git_source"
        next unless cred["username"] && cred["password"]

        authenticated_url =
          "https://#{cred.fetch('username')}:#{cred.fetch('password')}" \
          "@#{cred.fetch('host')}"

        git_store_content += authenticated_url + "\n"
        configure_git_to_use_https(cred.fetch("host"))
      end

      # Save the file
      File.write("git.store", git_store_content)
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/PerceivedComplexity

    sig { params(host: String).void }
    def self.configure_git_to_use_https(host)
      # NOTE: we use --global here (rather than --system) so that Dependabot
      # can be run without privileged access
      run_shell_command(
        "git config --global --replace-all url.https://#{host}/." \
        "insteadOf ssh://git@#{host}/"
      )
      run_shell_command(
        "git config --global --add url.https://#{host}/." \
        "insteadOf ssh://git@#{host}:"
      )
      run_shell_command(
        "git config --global --add url.https://#{host}/." \
        "insteadOf git@#{host}:"
      )
      run_shell_command(
        "git config --global --add url.https://#{host}/." \
        "insteadOf git@#{host}/"
      )
      run_shell_command(
        "git config --global --add url.https://#{host}/." \
        "insteadOf git://#{host}/"
      )
    end

    sig { params(path: String).void }
    def self.reset_git_repo(path)
      Dir.chdir(path) do
        run_shell_command("git reset HEAD --hard")
        run_shell_command("git clean -fx")
      end
    end

    sig { returns(T::Array[String]) }
    def self.find_safe_directories
      # to preserve safe directories from global .gitconfig
      output, process = Open3.capture2("git config --global --get-all safe.directory")
      safe_directories = []
      safe_directories = output.split("\n").compact if process.success?
      safe_directories
    end

    # rubocop:disable Metrics/PerceivedComplexity
    sig do
      params(
        command: String,
        allow_unsafe_shell_command: T::Boolean,
        cwd: T.nilable(String),
        env: T.nilable(T::Hash[String, String]),
        fingerprint: T.nilable(String),
        stderr_to_stdout: T::Boolean,
        command_type: Symbol,
        timeout: Integer
      ).returns(String)
    end
    def self.run_shell_command(command,
                               allow_unsafe_shell_command: false,
                               cwd: nil,
                               env: {},
                               fingerprint: nil,
                               stderr_to_stdout: true,
                               command_type: :network,
                               timeout: -1)
      start = Time.now
      cmd = allow_unsafe_shell_command ? command : escape_command(command)

      puts cmd if ENV["DEBUG_HELPERS"] == "true"

      opts = {}
      opts[:chdir] = cwd if cwd

      env_cmd = [env || {}, cmd, opts].compact
      if Experiments.enabled?(:enable_shared_helpers_command_timeout)

        stdout, stderr, process, _elapsed_time = CommandHelpers.capture3_with_timeout(
          env_cmd,
          stderr_to_stdout: stderr_to_stdout,
          command_type: command_type,
          timeout: timeout
        )

      elsif stderr_to_stdout
        stdout, process = Open3.capture2e(env || {}, cmd, opts)
      else
        stdout, stderr, process = Open3.capture3(env || {}, cmd, opts)
      end

      time_taken = Time.now - start

      # Raise an error with the output from the shell session if the
      # command returns a non-zero status
      return stdout || "" if process&.success?

      error_context = {
        command: cmd,
        fingerprint: fingerprint,
        time_taken: time_taken,
        process_exit_value: process.to_s
      }

      check_out_of_disk_memory_error(stderr, error_context)

      raise SharedHelpers::HelperSubprocessFailed.new(
        message: stderr_to_stdout ? (stdout || "") : "#{stderr}\n#{stdout}",
        error_context: error_context
      )
    end
    # rubocop:enable Metrics/PerceivedComplexity

    sig { params(stderr: T.nilable(String), error_context: T::Hash[Symbol, String]).void }
    def self.check_out_of_disk_memory_error(stderr, error_context)
      if stderr&.include?("No space left on device") || stderr&.include?("Out of diskspace")
        raise HelperSubprocessFailed.new(
          message: "No space left on device",
          error_class: "Dependabot::OutOfDisk",
          error_context: error_context
        )
      elsif stderr&.include?("MemoryError")
        raise HelperSubprocessFailed.new(
          message: "MemoryError",
          error_class: "Dependabot::OutOfMemory",
          error_context: error_context
        )
      end
    end

    sig { params(command: String, stdin_data: String, env: T.nilable(T::Hash[String, String])).returns(String) }
    def self.helper_subprocess_bash_command(command:, stdin_data:, env:)
      escaped_stdin_data = stdin_data.gsub("\"", "\\\"")
      env_keys = env ? env.compact.map { |k, v| "#{k}=#{v}" }.join(" ") + " " : ""
      "$ cd #{Dir.pwd} && echo \"#{escaped_stdin_data}\" | #{env_keys}#{command}"
    end
    private_class_method :helper_subprocess_bash_command
  end
end
