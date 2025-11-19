# typed: false
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "helpers"

# Tests for ecosystem scaffold rake task
module EcosystemScaffoldTests
  extend RakeTestHelpers

  module_function

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
  def test_ecosystem_scaffold?
    puts "\n=== Testing rake ecosystem:scaffold ==="

    test_dir = Dir.mktmpdir
    original_dir = Dir.pwd

    begin
      Dir.chdir(test_dir)

      # Test with valid ecosystem name
      result = run_command("cd #{original_dir} && bundle exec rake ecosystem:scaffold[test_eco_temp,skip]")

      unless result[:success]
        puts "✗ ecosystem:scaffold FAILED to execute"
        puts "STDERR: #{result[:stderr]}"
        return false
      end

      Dir.chdir(original_dir)

      # Verify key files were created
      required_files = [
        "test_eco_temp/lib/dependabot/test_eco_temp.rb",
        "test_eco_temp/lib/dependabot/test_eco_temp/file_fetcher.rb",
        "test_eco_temp/lib/dependabot/test_eco_temp/file_parser.rb",
        "test_eco_temp/lib/dependabot/test_eco_temp/update_checker.rb",
        "test_eco_temp/lib/dependabot/test_eco_temp/file_updater.rb",
        "test_eco_temp/spec/dependabot/test_eco_temp/file_fetcher_spec.rb",
        "test_eco_temp/README.md",
        "test_eco_temp/dependabot-test_eco_temp.gemspec"
      ]

      all_exist = true
      required_files.each do |file|
        if File.exist?(file)
          puts "✓ #{file} was created"
        else
          puts "✗ #{file} is MISSING"
          all_exist = false
        end
      end

      # Verify optional files have deletion comments
      if File.exist?("test_eco_temp/lib/dependabot/test_eco_temp/metadata_finder.rb")
        metadata_finder = File.read("test_eco_temp/lib/dependabot/test_eco_temp/metadata_finder.rb")
        if metadata_finder.include?("OPTIONAL")
          puts "✓ Optional files have deletion comments"
        else
          puts "✗ Optional files missing deletion comments"
          all_exist = false
        end
      else
        puts "✗ metadata_finder.rb was not created"
        all_exist = false
      end

      # Test that running again with skip mode works
      result = run_command("bundle exec rake ecosystem:scaffold[test_eco_temp,skip]")
      if result[:success]
        puts "✓ Scaffold works with existing directory (skip mode)"
      else
        puts "✗ Scaffold failed with existing directory (skip mode)"
        all_exist = false
      end

      # Clean up
      FileUtils.rm_rf("test_eco_temp")

      # Test error handling - invalid name
      result = run_command("bundle exec rake ecosystem:scaffold[Invalid-Name]")
      if result[:success]
        puts "✗ Invalid name was not rejected"
        all_exist = false
      else
        puts "✓ Invalid name is rejected"
      end

      all_exist
    ensure
      Dir.chdir(original_dir) if Dir.pwd != original_dir
      FileUtils.rm_rf(test_dir)
      FileUtils.rm_rf("test_eco_temp")
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
end
