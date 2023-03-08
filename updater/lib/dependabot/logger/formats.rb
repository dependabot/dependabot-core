# frozen_string_literal: true

require "logger"

# Provides Logger::Formatter classes specific to the Updater project to augment
# the global log helper defined in common/lib/dependabot/logger.rb
module Dependabot
  module Logger
    class BasicFormatter < ::Logger::Formatter
      # Strip out timestamps as these are included in the runner's logger
      def call(severity, _datetime, _progname, msg)
        "#{severity} #{msg2str(msg)}\n"
      end
    end

    class JobFormatter < ::Logger::Formatter
      def initialize(job_id)
        @job_id = job_id
      end

      def call(severity, _datetime, _progname, msg)
        "#{severity} <job_#{job_id}> #{msg2str(msg)}\n"
      end

      private

      def job_id
        @job_id || "unknown_id"
      end
    end
  end
end
