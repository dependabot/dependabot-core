# typed: strong
# frozen_string_literal: true

require "timeout"
require "sorbet-runtime"
require "shellwords"

module Dependabot
  module CommandHelpers
    extend T::Sig

    module TIMEOUTS
      NO_TIME_OUT = -1 # No timeout
      GRACEFULLY_STOP = 5 # 5 seconds for graceful termination
      LOCAL = 30 # 30 seconds
      NETWORK = 120 # 2 minutes
      LONG_RUNNING = 300 # 5 minutes
      DEFAULT = 900 # 15 minutes
    end

    OutputObserver = T.type_alias do
      T.nilable(T.proc.params(data: String).returns(T::Hash[Symbol, T.anything]))
    end

    Environment = T.type_alias { T::Hash[String, String] }
    SpawnOptions = T.type_alias { T::Hash[Symbol, T.anything] }

    EnvCmdItem = T.type_alias do
      T.any(
        String,
        T::Array[String],
        Environment,
        SpawnOptions
      )
    end

    class ProcessStatus
      extend T::Sig

      sig { params(process_status: T.nilable(Process::Status), custom_exitstatus: T.nilable(Integer)).void }
      def initialize(process_status, custom_exitstatus = nil)
        @process_status = process_status
        @custom_exitstatus = custom_exitstatus
      end

      # Return the exit status, either from the process status or the custom one
      sig { returns(Integer) }
      def exitstatus
        @custom_exitstatus || @process_status&.exitstatus || 0
      end

      # Determine if the process was successful
      sig { returns(T::Boolean) }
      def success?
        @custom_exitstatus.nil? ? @process_status&.success? || false : @custom_exitstatus.zero?
      end

      # Return the PID of the process (if available)
      sig { returns(T.nilable(Integer)) }
      def pid
        @process_status&.pid
      end

      sig { returns(T.nilable(Integer)) }
      def termsig
        @process_status&.termsig
      end

      # String representation of the status
      sig { returns(String) }
      def to_s
        if @custom_exitstatus
          "pid #{pid || 'unknown'}: exit #{@custom_exitstatus} (custom status)"
        else
          @process_status&.to_s || "unknown status"
        end
      end
    end

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    sig do
      params(
        env_cmd: T::Array[EnvCmdItem],
        stdin_data: T.nilable(String),
        stderr_to_stdout: T::Boolean,
        timeout: Integer,
        output_observer: OutputObserver
      ).returns([T.nilable(String), T.nilable(String), T.nilable(ProcessStatus), Float])
    end
    def self.capture3_with_timeout(
      env_cmd,
      stdin_data: nil,
      stderr_to_stdout: false,
      timeout: TIMEOUTS::DEFAULT,
      output_observer: nil
    )
      stdout = T.let("", String)
      stderr = T.let("", String)
      status = T.let(nil, T.nilable(ProcessStatus))
      pid = T.let(nil, T.nilable(Integer))
      start_time = Time.now

      begin
        stdout_io, stderr_io, wait_thr = open_process(env_cmd)
        begin
          pid = wait_thr.pid
          command_string = command_string_for_logging(env_cmd)
          log_level = short_git_config_command?(command_string) ? :debug : :info
          first_item = env_cmd.first
          sanitized_env_cmd = T.let(
            if first_item.is_a?(Hash)
              environment = extract_environment(env_cmd.dup)
              [T.must(SharedHelpers.sanitize_env_for_logging(environment)), *env_cmd.drop(1)]
            else
              env_cmd
            end,
            T::Array[EnvCmdItem]
          )
          command_for_log = sanitized_env_cmd.map { |item| item.is_a?(Array) ? item.first : item }.join(" ")
          Dependabot.logger.public_send(log_level, "Started process PID: #{pid} with command: #{command_for_log}")

          # Write to stdin if input data is provided
          begin
            stdout_io.write(stdin_data) if stdin_data
          rescue Errno::EPIPE
            # Process exited before reading stdin - continue to collect output
          end
          stdout_io.close_write

          stdout_io.sync = true
          stderr_io.sync = true

          # Array to monitor both stdout and stderr
          ios = [stdout_io, stderr_io]

          last_output_time = Time.now # Track the last time output was received

          until ios.empty?
            if timeout.positive?
              # Calculate remaining timeout dynamically
              remaining_timeout = timeout - (Time.now - last_output_time)

              # Raise an error if timeout is exceeded
              if remaining_timeout <= 0
                Dependabot.logger.warn("Process PID: #{pid} timed out after #{timeout}s. Terminating...")
                terminate_process(pid)
                status = ProcessStatus.new(wait_thr.value, 124)
                raise Timeout::Error, "Timed out due to inactivity after #{timeout} seconds"
              end
            end

            # Use IO.select with a dynamically calculated short timeout
            ready_ios = IO.select(ios, nil, nil, 0)

            # Process ready IO streams
            ready_ios&.first&.each do |io|
              # 1. Read data from the stream
              io.set_encoding("BINARY")
              data = io.read_nonblock(1024)

              # 2. Force encoding to UTF-8 (for proper conversion)
              data.force_encoding("UTF-8")

              # 3. Convert to UTF-8 safely, handling invalid/undefined bytes
              data = data.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

              # Reset the timeout if data is received
              last_output_time = Time.now unless data.empty?

              # 4. Append data to the appropriate stream
              if io == stdout_io
                stdout += data
              else
                stderr += data unless stderr_to_stdout
                stdout += data if stderr_to_stdout
              end

              # Observe the output if an observer is provided.
              # This allows for custom handling of process output, including early termination.
              observation = output_observer&.call(data)

              if observation&.dig(:gracefully_stop)
                message = observation[:reason] || "Terminated by output_observer"
                # If the observer indicates a graceful stop, terminate the process
                # by adjusting the remaining timeout
                timeout = [timeout, ((Time.now - last_output_time) + TIMEOUTS::GRACEFULLY_STOP).to_i].min
                Dependabot.logger.warn("Terminating process due to observer signal: #{message}")
              end
            rescue EOFError
              # Remove the stream when EOF is reached
              ios.delete(io)
            rescue IO::WaitReadable
              # Continue when IO is not ready yet
              next
            end
          end

          status = ProcessStatus.new(wait_thr.value)
          Dependabot.logger.public_send(log_level, "Process PID: #{pid} completed with status: #{status}")
        ensure
          stdout_io.close unless stdout_io.closed?
          stderr_io.close unless stderr_io.closed?
          wait_thr.join
        end
      rescue Timeout::Error => e
        Dependabot.logger.error("Process PID: #{pid} failed due to timeout: #{e.message}")
        terminate_process(pid)

        # Append timeout message only to stderr without interfering with stdout
        stderr += "\n#{e.message}" unless stderr_to_stdout
        stdout += "\n#{e.message}" if stderr_to_stdout
      rescue Errno::ENOENT => e
        Dependabot.logger.error("Command failed: #{e.message}")
        stderr += e.message unless stderr_to_stdout
        stdout += e.message if stderr_to_stdout
      end

      elapsed_time = Time.now - start_time
      log_level = short_git_config_command?(command_string_for_logging(env_cmd)) ? :debug : :info
      Dependabot.logger.public_send(log_level, "Total execution time: #{elapsed_time.round(2)} seconds")
      [stdout, stderr, status, elapsed_time]
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/CyclomaticComplexity

    sig { params(env_cmd: T::Array[EnvCmdItem]).returns([IO, IO, Process::Waiter]) }
    def self.open_process(env_cmd)
      process_io = T.let(nil, T.nilable(IO))
      stderr_io = T.let(nil, T.nilable(IO))
      stderr_writer = T.let(nil, T.nilable(IO))
      arguments = env_cmd.dup
      environment = extract_environment(arguments)
      options = extract_options(arguments)
      command = command_for_popen(arguments)

      stderr_io, stderr_writer = IO.pipe
      options[:err] = stderr_writer
      process_io = T.cast(IO.popen(environment, command, "r+", options), IO)
      stderr_writer.close

      wait_thread = T.cast(Process.detach(process_io.pid), Process::Waiter)
      [process_io, stderr_io, wait_thread]
    rescue StandardError
      process_io.close if process_io && !process_io.closed?
      stderr_io.close if stderr_io && !stderr_io.closed?
      stderr_writer.close if stderr_writer && !stderr_writer.closed?
      raise
    end
    private_class_method :open_process

    sig { params(arguments: T::Array[EnvCmdItem]).returns(Environment) }
    def self.extract_environment(arguments)
      return {} unless arguments.first.is_a?(Hash)

      T.cast(arguments.shift, Environment)
    end
    private_class_method :extract_environment

    sig { params(arguments: T::Array[EnvCmdItem]).returns(SpawnOptions) }
    def self.extract_options(arguments)
      return {} unless arguments.last.is_a?(Hash)

      T.cast(arguments.pop, SpawnOptions).dup
    end
    private_class_method :extract_options

    sig do
      params(arguments: T::Array[EnvCmdItem])
        .returns(T.any(String, T::Array[T.any(String, T::Array[String])]))
    end
    def self.command_for_popen(arguments)
      raise ArgumentError, "command must not be empty" if arguments.empty?

      first_argument = arguments.first
      return first_argument if arguments.one? && first_argument.is_a?(String)

      T.cast(arguments, T::Array[T.any(String, T::Array[String])])
    end
    private_class_method :command_for_popen

    # Terminate a process by PID
    sig { params(pid: T.nilable(Integer)).void }
    def self.terminate_process(pid)
      return unless pid

      begin
        if process_alive?(pid)
          Process.kill("TERM", pid) # Attempt graceful termination
          sleep(0.5) # Allow process to terminate
        end
        if process_alive?(pid)
          Process.kill("KILL", pid) # Forcefully kill if still running
        end
      rescue Errno::EPERM
        Dependabot.logger.error("Insufficient permissions to terminate process: #{pid}")
      ensure
        begin
          Process.waitpid(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          # Process has already exited
        end
      end
    end

    # Check if the process is still alive
    sig { params(pid: T.nilable(Integer)).returns(T::Boolean) }
    def self.process_alive?(pid)
      return false if pid.nil?

      begin
        Process.kill(0, pid) # Check if the process exists
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        Dependabot.logger.error("Insufficient permissions to check process: #{pid}")
        false
      end
    end

    # Escape shell commands to ensure safe execution
    sig { params(command: String).returns(String) }
    def self.escape_command(command)
      command_parts = command.split.map(&:strip).reject(&:empty?)
      Shellwords.join(command_parts)
    end

    sig { params(env_cmd: T::Array[EnvCmdItem]).returns(T.nilable(String)) }
    def self.command_string_for_logging(env_cmd)
      command_parts = env_cmd.filter_map do |item|
        case item
        when Array then item.first
        when String then item
        end
      end

      command_parts.join(" ") unless command_parts.empty?
    end
    private_class_method :command_string_for_logging

    sig { params(command: T.nilable(String)).returns(T::Boolean) }
    def self.short_git_config_command?(command)
      return false if command.nil?

      command.start_with?("git config --global ")
    end
    private_class_method :short_git_config_command?
  end
end
