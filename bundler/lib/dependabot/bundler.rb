# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/bundler/file_fetcher"
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/metadata_finder"
require "dependabot/bundler/requirement"
require "dependabot/bundler/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler.
  register_label_details("bundler", name: "ruby", colour: "ce2d2d")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "bundler",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("runtime")
    return true if groups.include?("default")

    groups.any? { |g| g.include?("prod") }
  end
)

module Dependabot
  def self.with_timer(message)
    start = Time.now.to_i
    Dependabot.logger.debug("Starting #{message}")
    yield
  ensure
    Dependabot.logger.debug("Finished #{message} in #{Time.now.to_i - start} seconds")
  end

  module SharedHelpers
    def self.run_helper_subprocess(command:, function:, args:, env: nil, stderr_to_stdout: false, allow_unsafe_shell_command: false)
      start = Time.now
      stdin_data = JSON.dump(function: function, args: args)
      cmd = allow_unsafe_shell_command ? command : escape_command(command)

      env_cmd = [env, cmd].compact
      stdout, stderr, process = Open3.capture3(*env_cmd, stdin_data: stdin_data)
      time_taken = Time.now - start

      Dependabot.logger.debug(stderr)

      stdout = "#{stderr}\n#{stdout}" if stderr_to_stdout

      response = JSON.parse(stdout)
      return response["result"] if process.success?

      raise HelperSubprocessFailed.new(
        message: response["error"],
        error_class: response["error_class"],
        error_context: {
          command: command,
          function: function,
          args: args,
          time_taken: time_taken,
          stderr_output: stderr ? stderr[0..50_000] : "", # Truncate to ~100kb
          process_exit_value: process.to_s,
          process_termsig: process.termsig
        },
        trace: response["trace"]
      )
    rescue JSON::ParserError
      raise HelperSubprocessFailed.new(
        message: stdout || "No output from command",
        error_class: "JSON::ParserError",
        error_context: {
          command: command,
          function: function,
          args: args,
          time_taken: time_taken,
          stderr_output: stderr ? stderr[0..50_000] : "", # Truncate to ~100kb
          process_exit_value: process.to_s,
          process_termsig: process.termsig
        }
      )
    end
  end
end
