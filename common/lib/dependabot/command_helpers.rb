# typed: strict
# frozen_string_literal: true

require "open3"
require "timeout"
require "sorbet-runtime"
require "shellwords"

module Dependabot
  module CommandHelpers
    extend T::Sig

    module TIMEOUTS
      NO_TIME_OUT = -1 # No timeout
      LOCAL = 30 # 30 seconds
      NETWORK = 120 # 2 minutes
      LONG_RUNNING = 300 # 5 minutes
      DEFAULT = 900 # 15 minutes
    end

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

    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/MethodLength
    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    sig do
      params(
        env_cmd: T::Array[T.any(T::Hash[String, String], String)],
        stdin_data: T.nilable(String),
        stderr_to_stdout: T::Boolean,
        timeout: Integer
      ).returns([T.nilable(String), T.nilable(String), T.nilable(ProcessStatus), Float])
    end
    def self.capture3_with_timeout(
      env_cmd,
      stdin_data: nil,
      stderr_to_stdout: false,
      timeout: TIMEOUTS::DEFAULT
    )

      stdout = T.let("", String)
      stderr = T.let("", String)
      status = T.let(nil, T.nilable(ProcessStatus))
      pid = T.let(nil, T.untyped)
      start_time = Time.now

      begin
        T.unsafe(Open3).popen3(*env_cmd) do |stdin, stdout_io, stderr_io, wait_thr| # rubocop:disable Metrics/BlockLength
          pid = wait_thr.pid
          Dependabot.logger.info("Started process PID: #{pid} with command: #{env_cmd.join(' ')}")

          # Write to stdin if input data is provided
          stdin&.write(stdin_data) if stdin_data
          stdin&.close

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
                                                    rescue EOFError
                                                      # Remove the stream when EOF is reached
                                                      ios.delete(io)
                                                    rescue IO::WaitReadable
                                                      # Continue when IO is not ready yet
                                                      next
            end
          end

          status = ProcessStatus.new(wait_thr.value)
          Dependabot.logger.info("Process PID: #{pid} completed with status: #{status}")
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
      Dependabot.logger.info("Total execution time: #{elapsed_time.round(2)} seconds")
      [stdout, stderr, status, elapsed_time]
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/MethodLength
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/CyclomaticComplexity

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
  end
end
