# frozen_string_literal: true

require "logger"

# Provides Logger::Formatter classes specific to the Updater project to augment
# the global log helper defined in common/lib/dependabot/logger.rb
module Dependabot
  module Logger
    TIME_FORMAT = "%Y/%m/%d %H:%M:%S"

    class BasicFormatter < ::Logger::Formatter
      def call(severity, _datetime, _progname, msg)
        "#{Time.now.strftime(TIME_FORMAT)} #{severity} #{msg2str(msg)}\n"
      end
    end

    class JobFormatter < ::Logger::Formatter
      CLI_ID = "cli"
      UNKNOWN_ID = "unknown_id"

      def initialize(job_id)
        @job_id = job_id
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

      def job_prefix
        return @job_prefix if defined? @job_prefix
        # The dependabot/cli tool uses a placeholder value since it does not
        # have an actual Job ID issued by the service.
        #
        # Let's just omit the prefix if this is the case.
        return @job_prefix = nil if @job_id == CLI_ID

        @job_prefix = "<job_#{@job_id || UNKNOWN_ID}>"
      end
    end
  end
end
