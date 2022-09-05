# frozen_string_literal: true

$LOAD_PATH.unshift(__dir__ + "/../lib")

require "raven"
require "dependabot/setup"
require "dependabot/end_to_end_job"

class UpdaterKilledError < StandardError; end

trap("TERM") do
  puts "Received SIGTERM"
  error = UpdaterKilledError.new("Updater process killed with SIGTERM")
  extra = { update_job_id: ENV.fetch("DEPENDABOT_JOB_ID", nil) }
  Raven.capture_exception(error, extra: extra)
  exit
end

begin
  Dependabot::EndToEndJob.new.run
rescue Dependabot::RunFailure
  exit 1
end
