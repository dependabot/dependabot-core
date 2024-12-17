# typed: strict
# frozen_string_literal: true

require "open3"
require "timeout"
require "sorbet-runtime"
require "shellwords"

module Dependabot
  module CommandHelpers
    extend T::Sig

    class ProcessStatus
      extend T::Sig

      sig { params(process_status: Process::Status, custom_exitstatus: T.nilable(Integer)).void }
      def initialize(process_status, custom_exitstatus = nil)
        @process_status = process_status
        @custom_exitstatus = custom_exitstatus
      end

      # Return the exit status, either from the process status or the custom one
      sig { returns(Integer) }
      def exitstatus
        @custom_exitstatus || @process_status.exitstatus || 0
      end

      # Determine if the process was successful
      sig { returns(T::Boolean) }
      def success?
        @custom_exitstatus.nil? ? @process_status.success? || false : @custom_exitstatus.zero?
      end

      # Return the PID of the process (if available)
      sig { returns(T.nilable(Integer)) }
      def pid
        @process_status.pid
      end

      sig { returns(T.nilable(Integer)) }
      def termsig
        @process_status.termsig
      end

      # String representation of the status
      sig { returns(String) }
      def to_s
        if @custom_exitstatus
          "pid #{pid || 'unknown'}: exit #{@custom_exitstatus} (custom status)"
        else
          @process_status.to_s
        end
      end
    end

    DEFAULT_TIMEOUTS = T.let({
      no_time_out: -1,  # No timeout
      local: 30,        # Local commands
      network: 120,     # Network-dependent commands
      long_running: 300 # Long-running tasks (e.g., builds)
    }.freeze, T::Hash[T.untyped, T.untyped])

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    sig do
      params(
        env_cmd: T::Array[T.any(T::Hash[String, String], String)],
        stdin_data: T.nilable(String),
        stderr_to_stdout: T::Boolean,
        command_type: Symbol,
        timeout: Integer
      ).returns([T.nilable(String), T.nilable(String), T.nilable(ProcessStatus), Float])
    end
    def self.capture3_with_timeout(
      env_cmd,
      stdin_data: nil,
      stderr_to_stdout: false,
      command_type: :network,
      timeout: -1
    )
      # Assign default timeout based on command type if timeout < 0
      timeout = DEFAULT_TIMEOUTS[command_type] if timeout.negative?

      stdout = T.let("", String)
      stderr = T.let("", String)
      status = T.let(nil, T.nilable(ProcessStatus))
      pid = T.let(nil, T.untyped)
      start_time = Time.now

      begin
        T.unsafe(Open3).popen3(*env_cmd) do |stdin, stdout_io, stderr_io, wait_thr|
          pid = wait_thr.pid
          stdin&.write(stdin_data) if stdin_data
          stdin&.close

          stdout_io.sync = true
          stderr_io.sync = true

          # Array to monitor both stdout and stderr
          ios = [stdout_io, stderr_io]

          last_output_time = Time.now # Track the last time output was received

          until ios.empty?
            # Calculate remaining timeout dynamically
            remaining_timeout = timeout - (Time.now - last_output_time)

            # Raise an error if timeout is exceeded
            if remaining_timeout <= 0
              terminate_process(pid)
              status = ProcessStatus.new(wait_thr.value, 124)
              raise Timeout::Error, "Timed out due to inactivity after #{timeout} seconds"
            end

            # Use IO.select with a dynamically calculated short timeout
            ready_ios = IO.select(ios, nil, nil, [0.1, remaining_timeout].min)

            # Process ready IO streams
            ready_ios&.first&.each do |io|
              data = io.read_nonblock(1024)

              data.force_encoding("UTF-8").scrub! # Normalize to UTF-8 and replace invalid characters

              last_output_time = Time.now
              if io == stdout_io
                stdout += data
              else
                stderr += data unless stderr_to_stdout
                stdout += data if stderr_to_stdout
              end
            rescue EOFError
              ios.delete(io)
            rescue IO::WaitReadable
              next
            end
          end

          status = ProcessStatus.new(wait_thr.value)
        end
      rescue Timeout::Error => e
        stderr += e.message unless stderr_to_stdout
        stdout += e.message if stderr_to_stdout
      rescue Errno::ENOENT => e
        stderr += e.message unless stderr_to_stdout
        stdout += e.message if stderr_to_stdout
      end

      elapsed_time = Time.now - start_time
      [stdout, stderr, status, elapsed_time]
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/CyclomaticComplexity

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

    sig { params(pid: T.nilable(Integer)).returns(T::Boolean) }
    def self.process_alive?(pid)
      return false if pid.nil? # No PID, consider process not alive

      begin
        Process.kill(0, pid) # Check if the process exists
        true # Process is still alive
      rescue Errno::ESRCH
        false # Process does not exist (terminated successfully)
      rescue Errno::EPERM
        Dependabot.logger.error("Insufficient permissions to check process: #{pid}")
        false # Assume process not alive due to lack of permissions
      end
    end

    sig { params(command: String).returns(String) }
    def self.escape_command(command)
      command_parts = command.split.map(&:strip).reject(&:empty?)
      Shellwords.join(command_parts)
    end
  end
end
