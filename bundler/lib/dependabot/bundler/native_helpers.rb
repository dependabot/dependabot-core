# frozen_string_literal: true

require "bundler"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    module NativeHelpers
      Result = Struct.new(:command, :stdout, :stderr, :status, :duration)

      def self.popen(command, path = nil, env = {}, &block)
        result = popen_with_detail(command, path, env, &block)

        ["#{result.stdout}#{result.stderr}", result.status&.exitstatus]
      end

      def self.popen_with_detail(command, path = Dir.pwd, env = {})
        FileUtils.mkdir_p(path) unless File.directory?(path)

        captured_stdout = ""
        captured_stderr = ""
        exit_status = nil
        start = Time.now

        Open3.popen3(env.merge("PWD" => path), *Array(command), { chdir: path }) do |stdin, stdout, stderr, wait_thr|
          out_reader = Thread.new { stdout.read }
          err_reader = Thread.new do
            result = ""
            until stderr.eof? do
              line = stderr.readline
              Dependabot.logger.debug(line)
              result += line
            end
            result
          rescue => e
            result
          end

          yield(stdin) if block_given?

          stdin.close
          captured_stdout = out_reader.value
          captured_stderr = err_reader.value
          exit_status = wait_thr.value
        end
        Result.new(command, captured_stdout, captured_stderr, exit_status, Time.now - start)
      end

      def self.execute(command:, function:, args:, env: nil)
        Dependabot.logger.debug(command)
        env_cmd = [env, ::Dependabot::SharedHelpers.escape_command(command)].compact
        # stdout, stderr, process = Open3.capture3(*env_cmd, stdin_data: JSON.dump(function: function, args: args))

        result = popen_with_detail(::Dependabot::SharedHelpers.escape_command(command), Dir.pwd, env) do |stdin|
          stdin.write(JSON.dump(function: function, args: args))
        end

        Dependabot.logger.debug(result.stderr)

        response = JSON.parse(result.stdout)
        if result.status.success?
          return response["result"]
        end

        raise ::Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: response["error"],
          error_class: response["error_class"],
          error_context: {
            command: command,
            function: function,
            args: args,
            time_taken: result.duration,
            stderr_output: result.stderr ? result.stderr[0..50_000] : "", # Truncate to ~100kb
            process_exit_value: result.status.to_s,
            process_termsig: result.status.termsig
          },
          trace: response["trace"]
        )
      rescue JSON::ParserError
        raise ::Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: result.stdout || "No output from command",
          error_class: "JSON::ParserError",
          error_context: {
            command: command,
            function: function,
            args: args,
            time_taken: result.duration,
            stderr_output: result.stderr ? result.stderr[0..50_000] : "", # Truncate to ~100kb
            process_exit_value: result.status.to_s,
            process_termsig: result.status.termsig
          }
        )
      end

      def self.run_bundler_subprocess(function:, args:, bundler_version:)
        # Run helper suprocess with all bundler-related ENV variables removed
        bundler_major_version = bundler_version.split(".").first
        ::Bundler.with_original_env do
          Dependabot.with_timer("run_bundler_subprocess") do
            execute(
              command: helper_path(bundler_version: bundler_major_version),
              function: function,
              args: args,
              env: {
                # Bundler will pick the matching installed major version
                "BUNDLER_VERSION" => bundler_version,
                "BUNDLE_GEMFILE" => File.join(versioned_helper_path(bundler_version: bundler_major_version), "Gemfile"),
                # Prevent the GEM_HOME from being set to a folder owned by root
                "GEM_HOME" => File.join(versioned_helper_path(bundler_version: bundler_major_version), ".bundle")
              }
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          # TODO: Remove once we stop stubbing out the V2 native helper
          raise Dependabot::NotImplemented, e.message if e.error_class == "Functions::NotImplementedError"

          raise
        end
      end

      def self.versioned_helper_path(bundler_version:)
        native_helper_version = "v#{bundler_version}"
        File.join(native_helpers_root, native_helper_version)
      end

      def self.helper_path(bundler_version:)
        "bundle exec ruby #{File.join(versioned_helper_path(bundler_version: bundler_version), 'run.rb')}"
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "bundler") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end
