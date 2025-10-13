# typed: false
# frozen_string_literal: true

require_relative "helpers"

# Tests for gems rake tasks
module GemsTaskTests
  extend RakeTestHelpers

  module_function

  def test_gems_clean?
    puts "\n=== Testing rake gems:clean ==="
    result = run_command("rake gems:clean")

    if result[:success]
      puts "✓ gems:clean executed successfully"
      true
    else
      puts "✗ gems:clean FAILED"
      puts "STDERR: #{result[:stderr]}"
      false
    end
  end
end
