# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module SharedHelpers
    # Captures diagnostic data about a single subprocess invocation so
    # that ecosystem-specific errors (e.g. `NoChangeError`) can be
    # debugged with full context: whether each command succeeded, its
    # duration, truncated output, and an optional content-changed flag
    # set by the caller after the command runs.
    #
    # Usage:
    #
    #   traces = []
    #   Dependabot::SharedHelpers::CommandTrace.record(
    #     traces: traces,
    #     package_manager: "npm",
    #     command: "install --package-lock-only",
    #     fingerprint: "install --package-lock-only"
    #   ) do
    #     run_native_command(...)
    #   end
    #
    # The trace is appended to `traces` before the block runs so that
    # callers retain visibility even when the block raises.
    class CommandTrace
      extend T::Sig

      # Truncation limits keep individual traces small enough to ship in
      # API payloads while still preserving useful debugging context.
      STDOUT_LIMIT = 4_096
      STDERR_LIMIT = 4_096
      ERROR_MESSAGE_LIMIT = 2_048

      sig { returns(String) }
      attr_reader :package_manager

      sig { returns(String) }
      attr_reader :command

      sig { returns(T.nilable(String)) }
      attr_reader :fingerprint

      sig { returns(Integer) }
      attr_accessor :duration_ms

      sig { returns(T::Boolean) }
      attr_accessor :success

      sig { returns(T.nilable(String)) }
      attr_accessor :error_class

      sig { returns(T.nilable(String)) }
      attr_accessor :error_message

      sig { returns(T.nilable(String)) }
      attr_accessor :stdout

      sig { returns(T.nilable(String)) }
      attr_accessor :stderr

      sig { returns(T.nilable(T::Boolean)) }
      attr_accessor :content_changed_after

      sig do
        params(
          package_manager: String,
          command: String,
          fingerprint: T.nilable(String)
        ).void
      end
      def initialize(package_manager:, command:, fingerprint: nil)
        @package_manager = package_manager
        @command = command
        @fingerprint = fingerprint
        @duration_ms = T.let(0, Integer)
        @success = T.let(false, T::Boolean)
        @error_class = T.let(nil, T.nilable(String))
        @error_message = T.let(nil, T.nilable(String))
        @stdout = T.let(nil, T.nilable(String))
        @stderr = T.let(nil, T.nilable(String))
        @content_changed_after = T.let(nil, T.nilable(T::Boolean))
      end

      # Hash representation suitable for inclusion in error payloads sent
      # via `record_update_job_error` and for log formatting. `nil` values
      # are dropped to keep payloads compact.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          package_manager: package_manager,
          command: command,
          fingerprint: fingerprint,
          duration_ms: duration_ms,
          success: success,
          error_class: error_class,
          error_message: error_message,
          stdout: stdout,
          stderr: stderr,
          content_changed_after: content_changed_after
        }.compact
      end

      # One-line, low-cardinality summary suitable for info-level logs.
      sig { returns(String) }
      def summary_line
        status = success ? "ok" : "fail"
        changed =
          if content_changed_after.nil?
            "content_changed=?"
          else
            "content_changed=#{content_changed_after}"
          end
        fp = fingerprint || command
        "[#{package_manager}] #{fp.inspect} status=#{status} duration_ms=#{duration_ms} #{changed}"
      end

      # Wraps a subprocess invocation, recording timing, success/failure
      # state, and (truncated) output into a new CommandTrace appended
      # to `traces`. Re-raises any exception after recording so callers
      # can keep their existing error-handling flow.
      sig do
        type_parameters(:R).params(
          traces: T::Array[CommandTrace],
          package_manager: String,
          command: String,
          fingerprint: T.nilable(String),
          block: T.proc.returns(T.type_parameter(:R))
        ).returns(T.type_parameter(:R))
      end
      def self.record(traces:, package_manager:, command:, fingerprint: nil, &block)
        trace = new(
          package_manager: package_manager,
          command: command,
          fingerprint: fingerprint
        )
        traces << trace

        start = T.let(Process.clock_gettime(Process::CLOCK_MONOTONIC), Numeric)
        begin
          result = block.call # rubocop:disable Performance/RedundantBlockCall
          record_success(trace, start, result)
          result
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          record_subprocess_failure(trace, start, e)
          raise
        rescue StandardError => e
          record_failure(trace, start, e)
          raise
        end
      end

      sig { params(trace: CommandTrace, start: Numeric, result: T.untyped).void }
      def self.record_success(trace, start, result)
        trace.duration_ms = elapsed_ms(start)
        trace.success = true
        trace.stdout = truncate(result.is_a?(String) ? result : nil, STDOUT_LIMIT)
      end
      private_class_method :record_success

      sig do
        params(
          trace: CommandTrace,
          start: Numeric,
          error: Dependabot::SharedHelpers::HelperSubprocessFailed
        ).void
      end
      def self.record_subprocess_failure(trace, start, error)
        record_failure(trace, start, error)
        stderr = error.error_context[:stderr_output]
        trace.stderr = truncate(stderr.is_a?(String) ? stderr : nil, STDERR_LIMIT)
      end
      private_class_method :record_subprocess_failure

      sig { params(trace: CommandTrace, start: Numeric, error: StandardError).void }
      def self.record_failure(trace, start, error)
        trace.duration_ms = elapsed_ms(start)
        trace.success = false
        trace.error_class = error.class.name
        trace.error_message = truncate(error.message, ERROR_MESSAGE_LIMIT)
      end
      private_class_method :record_failure

      sig { params(text: T.nilable(String), limit: Integer).returns(T.nilable(String)) }
      def self.truncate(text, limit)
        return nil if text.nil?
        return text if text.length <= limit

        dropped = text.length - limit
        "#{text[0, limit]}\n... [truncated #{dropped} chars]"
      end
      private_class_method :truncate

      sig { params(start: Numeric).returns(Integer) }
      def self.elapsed_ms(start)
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).to_i
      end
      private_class_method :elapsed_ms
    end
  end
end
