# typed: false
# frozen_string_literal: true

require_relative "helpers"

# Tests for rubocop rake tasks
module RubocopTaskTests
  extend RakeTestHelpers

  module_function

  def test_rubocop_sort?
    puts "\n=== Testing rake rubocop:sort ==="
    result = run_command("rake rubocop:sort")

    if result[:success]
      puts "✓ rubocop:sort executed successfully"

      # Verify the file was actually updated
      if File.exist?("omnibus/.rubocop.yml")
        puts "✓ omnibus/.rubocop.yml exists"
        true
      else
        puts "✗ omnibus/.rubocop.yml does not exist"
        false
      end
    else
      puts "✗ rubocop:sort FAILED"
      puts "STDERR: #{result[:stderr]}"
      false
    end
  end
end
