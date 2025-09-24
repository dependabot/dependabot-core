# typed: strong
# frozen_string_literal: true

require "logger"

# Provides Logger::Formatter classes specific to the Updater project to augment
# the global log helper defined in common/lib/dependabot/logger.rb
module Dependabot
  module Logger
    TIME_FORMAT = "%Y/%m/%d %H:%M:%S"

    class BasicFormatter < ::Logger::Formatter
      extend T::Sig

      sig do
        params(severity: String, _datetime: T.nilable(Time), _progname: T.nilable(String), msg: T.nilable(String))
          .returns(String)
      end
      def call(severity, _datetime, _progname, msg)
        "#{Time.now.strftime(TIME_FORMAT)} #{severity} #{msg2str(msg)}\n"
      end
    end

    class JobFormatter < ::Logger::Formatter
      extend T::Sig

      CLI_ID = "cli"
      UNKNOWN_ID = "unknown_id"

      sig { params(job_id: T.nilable(String)).void }
      def initialize(job_id)
        @job_id = job_id
      end

      sig do
        params(severity: String, _datetime: T.nilable(Time), _progname: T.nilable(String), msg: T.nilable(String))
          .returns(String)
      end
      def call(severity, _datetime, _progname, msg)
        [
          Time.now.strftime(TIME_FORMAT),
          severity,
          job_prefix,
          msg2str(msg)
        ].compact.join(" ") + "\n"
      end

      private

      sig { returns(T.nilable(String)) }
      def job_prefix
        @job_prefix ||= T.let(
          begin
            return nil if @job_id == CLI_ID

            "<job_#{@job_id || UNKNOWN_ID}>"
          end,
          T.nilable(String)
        )
      end
    end
  end
end
