# typed: false
# frozen_string_literal: true

require_relative "helpers"

# Tests for rake task listing and basic tasks
module RakefileStructureTests
  extend RakeTestHelpers

  module_function

  def test_task_list
    puts "\n=== Testing rake -AT (list all tasks) ==="
    result = run_command("rake -AT")

    expected_tasks = ["gems:build", "gems:clean", "gems:release", "rubocop:sort", "ecosystem:scaffold", "ecosystem:update_infrastructure"]

    expected_tasks.each do |task|
      if result[:stdout].include?(task)
        puts "✓ Task '#{task}' is available"
      else
        puts "✗ Task '#{task}' is MISSING"
        return false
      end
    end

    result[:success]
  end

  def test_rakefile_structure
    puts "\n=== Verifying Rakefile structure ==="

    required_files = [
      "Rakefile",
      "rakelib/gems.rake",
      "rakelib/rubocop.rake",
      "rakelib/ecosystem.rake",
      "rakelib/support/helpers.rb"
    ]

    all_exist = true
    required_files.each do |file|
      if File.exist?(file)
        puts "✓ #{file} exists"
      else
        puts "✗ #{file} is MISSING"
        all_exist = false
      end
    end

    all_exist
  end

  def test_helpers_loaded?
    puts "\n=== Testing that helpers are properly loaded ==="

    # Test that constants and methods from helpers.rb are available when rake tasks load them
    result = run_command("ruby -e \"load './Rakefile'; load 'rakelib/support/helpers.rb'; puts GEMSPECS.class\"")

    if result[:success] && result[:stdout].strip == "Array"
      puts "✓ GEMSPECS constant is loaded"
    else
      puts "✗ GEMSPECS constant failed to load"
      puts "STDOUT: #{result[:stdout]}"
      puts "STDERR: #{result[:stderr]}"
      return false
    end

    result = run_command(
      "ruby -e \"load './Rakefile'; load 'rakelib/support/helpers.rb'; puts RakeHelpers.respond_to?(:guard_tag_match)\""
    )

    if result[:success] && result[:stdout].strip == "true"
      puts "✓ RakeHelpers.guard_tag_match method is defined"
    else
      puts "✗ RakeHelpers.guard_tag_match method failed to load"
      puts "STDOUT: #{result[:stdout]}"
      puts "STDERR: #{result[:stderr]}"
      return false
    end

    true
  end
end
