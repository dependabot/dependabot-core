# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"
require "io/wait"
require "dependabot/error_report_context"

module Dependabot
  module NpmAndYarn
    class SubprocessDiagnosticProbe
      extend T::Sig

      TIMEOUT = 10
      MAX_OUTPUT_BYTES = 65_536
      VERSION = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
      EXECUTABLE = /\A(?:corepack )?(?:npm|pnpm|yarn)(?:@\d+(?:\.\d+){0,2}(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)?\z/

      sig { params(executable: String, env: T.nilable(T::Hash[String, String])).void }
      def initialize(executable:, env:)
        @executable = executable
        @env = T.let(
          (env || {}).merge("COREPACK_ENABLE_NETWORK" => "0", "COREPACK_ENABLE_DOWNLOAD_PROMPT" => "0"),
          T::Hash[String, String]
        )
      end

      sig { returns(ErrorReportContext::Context) }
      def context
        return {} unless EXECUTABLE.match?(@executable)

        deadline = monotonic_time + TIMEOUT
        version = probe_version(deadline)
        result = T.let({}, ErrorReportContext::Context)
        result["post-failure-package-manager-version"] = version if version
        registry_key = registry_key(version)
        return result unless registry_key

        output = capture(["config", "get", registry_key], deadline)
        hosts = registry_hosts(output)
        Dependabot.logger.warn("Could not parse post-failure global registry") if output && hosts.empty?
        result["post-failure-global-registry-hosts"] = hosts unless hosts.empty?
        result
      rescue StandardError => e
        Dependabot.logger.warn("Could not collect post-failure package manager context (#{e.class})")
        {}
      end

      private

      sig { params(deadline: Float).returns(T.nilable(String)) }
      def probe_version(deadline)
        output = capture(["--version"], deadline)
        return unless output

        version = output.lines.map(&:strip).reverse.find { |line| VERSION.match?(line) }
        Dependabot.logger.warn("Could not parse post-failure package manager version") unless version
        version
      end

      sig { params(version: T.nilable(String)).returns(T.nilable(String)) }
      def registry_key(version)
        return "registry" unless @executable.split.last.to_s.start_with?("yarn")
        return unless version

        version.split(".").first.to_i >= 2 ? "npmRegistryServer" : "registry"
      end

      sig { params(output: T.nilable(String)).returns(T::Array[String]) }
      def registry_hosts(output)
        output.to_s.lines.filter_map do |line|
          url = line.strip
          next unless url.match?(%r{\Ahttps?://}i) && !url.include?("${")

          host = ErrorReportContext.host_for(url)
          host unless host == ErrorReportContext::REDACTED
        end.uniq
      end

      sig { params(arguments: T::Array[String], deadline: Float).returns(T.nilable(String)) }
      def capture(arguments, deadline)
        return if monotonic_time >= deadline

        reader, writer = IO.pipe
        pid = T.let(nil, T.nilable(Integer))
        begin
          command = Shellwords.join(@executable.split + arguments)
          pid = Process.spawn(@env, command, in: File::NULL, out: writer, err: File::NULL, pgroup: true)
          writer.close
          read_output(reader, pid, deadline)
        ensure
          writer.close unless writer.closed?
          terminate_and_reap(pid) if pid
          reader.close unless reader.closed?
        end
      end

      sig { params(reader: IO, pid: Integer, deadline: Float).returns(T.nilable(String)) }
      def read_output(reader, pid, deadline)
        output = T.let(+"", String)
        eof = T.let(false, T::Boolean)
        loop do
          remaining = deadline - monotonic_time
          if remaining <= 0
            Dependabot.logger.warn("Post-failure package manager probe exceeded its wall-clock deadline")
            return
          end

          if eof
            status = Process.waitpid2(pid, Process::WNOHANG)
            if status
              return output if status.last.success?

              Dependabot.logger.warn("Post-failure package manager probe exited unsuccessfully")
              return
            end

            sleep([remaining, 0.01].min)
            next
          end
          next unless reader.wait_readable([remaining, 0.01].min)

          data = read_chunk(reader)
          eof = true if data.nil?
          next unless data.is_a?(String)

          if output.bytesize + data.bytesize > MAX_OUTPUT_BYTES
            Dependabot.logger.warn("Post-failure package manager probe exceeded its output limit")
            return
          end
          output << data
        end
      end

      sig { params(reader: IO).returns(T.nilable(String)) }
      def read_chunk(reader)
        reader.read_nonblock(4096)
      rescue IO::WaitReadable
        ""
      rescue EOFError
        nil
      end

      sig { params(pid: Integer).void }
      def terminate_and_reap(pid)
        begin
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH
          # The process group has already exited.
        end
        begin
          Process.waitpid(pid)
        rescue Errno::ECHILD
          # A successful probe was already reaped.
        end
      end

      sig { returns(Float) }
      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
      end
    end
  end
end
