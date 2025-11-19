# typed: false
# frozen_string_literal: true

require "open3"

# Helper module for running commands in tests
module RakeTestHelpers
  module_function

  def run_command(cmd)
    # In CI environments, prepend bundle exec to rake and ruby commands to ensure gems are available
    cmd = "bundle exec #{cmd}" if ENV["CI"] && cmd.start_with?("rake ", "ruby ")
    puts "Running: #{cmd}"
    stdout, stderr, status = Open3.capture3(cmd)
    {
      stdout: stdout,
      stderr: stderr,
      success: status.success?,
      exit_code: status.exitstatus
    }
  end
end
