# frozen_string_literal: true

require "tmpdir"
require "excon"
require "English"

module Dependabot
  module SharedHelpers
    BUMP_TMP_FILE_PREFIX = "dependabot_"
    BUMP_TMP_DIR_PATH = "tmp"

    class ChildProcessFailed < StandardError
      attr_reader :error_class, :error_message, :error_backtrace

      def initialize(error_class:, error_message:, error_backtrace:)
        @error_class = error_class
        @error_message = error_message
        @error_backtrace = error_backtrace

        msg = "Child process raised #{error_class} with message: "\
              "#{error_message}"
        super(msg)
        set_backtrace(error_backtrace)
      end
    end

    def self.in_a_temporary_directory
      Dir.mkdir(BUMP_TMP_DIR_PATH) unless Dir.exist?(BUMP_TMP_DIR_PATH)
      Dir.mktmpdir(BUMP_TMP_FILE_PREFIX, BUMP_TMP_DIR_PATH) do |dir|
        path = Pathname.new(dir).expand_path
        Dir.chdir(path) { yield(path) }
      end
    end

    def self.in_a_forked_process
      read, write = IO.pipe

      pid = fork do
        read.close
        result = yield
      rescue Exception => error # rubocop:disable Lint/RescueException
        result = { _error_details: { error_class: error.class.to_s,
                                     error_message: error.message,
                                     error_backtrace: error.backtrace } }
      ensure
        Marshal.dump(result, write)
        exit!(0)
      end

      write.close
      result = read.read
      Process.wait(pid)
      result = Marshal.load(result) # rubocop:disable Security/MarshalLoad

      return result unless result.is_a?(Hash) && result[:_error_details]
      raise ChildProcessFailed, result[:_error_details]
    end

    class HelperSubprocessFailed < StandardError
      def initialize(message, command)
        super(message)
        @command = command
      end
    end

    def self.run_helper_subprocess(command:, function:, args:, env: nil,
                                   popen_opts: {})
      raw_response = nil
      popen_args = [env, command, "w+"].compact
      IO.popen(*popen_args, **popen_opts) do |process|
        process.write(JSON.dump(function: function, args: args))
        process.close_write
        raw_response = process.read
      end

      response = JSON.parse(raw_response)
      return response["result"] if $CHILD_STATUS.success?

      raise HelperSubprocessFailed.new(response["error"], command)
    rescue JSON::ParserError
      raise HelperSubprocessFailed.new(raw_response, command) if raw_response
      raise HelperSubprocessFailed.new("No output from command", command)
    end

    def self.excon_middleware
      Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
    end
  end
end
