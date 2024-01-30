# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

$LOAD_PATH.unshift(T.must(__dir__) + "/../lib")

$stdout.sync = true

require "sentry-ruby"
require "dependabot/setup"
require "dependabot/file_fetcher_command"
require "debug" if ENV["DEBUG"]

class UpdaterKilledError < StandardError; end

trap("TERM") do
  puts "Received SIGTERM"
  error = UpdaterKilledError.new("Updater process killed with SIGTERM")
  tags = { "gh.dependabot_api.update_job.id": ENV.fetch("DEPENDABOT_JOB_ID", nil) }
  Sentry.capture_exception(error, tags: tags)
  exit
end

begin
  Dependabot::FileFetcherCommand.new.run
rescue Dependabot::RunFailure
  exit 1
end
