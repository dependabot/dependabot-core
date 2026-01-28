# typed: false
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "helpers"

# Tests for ecosystem infrastructure update rake task
module EcosystemInfrastructureUpdaterTests
  extend RakeTestHelpers

  module_function

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
  def test_ecosystem_update_infrastructure?
    puts "\n=== Testing rake ecosystem:update_infrastructure ==="

    test_dir = Dir.mktmpdir
    original_dir = Dir.pwd

    begin
      # First, scaffold a test ecosystem
      puts "  Setting up test ecosystem..."
      result = run_command("cd #{original_dir} && bundle exec rake ecosystem:scaffold[test_infra_eco,skip]")

      unless result[:success]
        puts "✗ Failed to scaffold test ecosystem"
        puts "STDERR: #{result[:stderr]}"
        return false
      end

      # Test infrastructure update
      puts "  Running infrastructure update..."
      result = run_command("cd #{original_dir} && bundle exec rake ecosystem:update_infrastructure[test_infra_eco]")

      unless result[:success]
        puts "✗ ecosystem:update_infrastructure FAILED to execute"
        puts "STDERR: #{result[:stderr]}"
        return false
      end

      Dir.chdir(original_dir)

      # Verify files were updated
      files_to_check = {
        ".github/ci-filters.yml" => "test_infra_eco",
        ".github/smoke-filters.yml" => "test_infra_eco",
        ".github/smoke-matrix.json" => "test_infra_eco",
        ".github/workflows/ci.yml" => "test_infra_eco",
        ".github/workflows/images-branch.yml" => "test_infra_eco",
        ".github/workflows/images-latest.yml" => "test_infra_eco",
        ".github/issue-labeler.yml" => "test_infra_eco",
        "bin/dry-run.rb" => "test_infra_eco",
        "script/dependabot" => "test_infra_eco",
        "omnibus/lib/dependabot/omnibus.rb" => "test_infra_eco",
        "updater/lib/dependabot/setup.rb" => "test_infra_eco",
        "rakelib/support/helpers.rb" => "test_infra_eco"
      }

      all_updated = true
      files_to_check.each do |file, pattern|
        if File.exist?(file)
          content = File.read(file)
          if content.include?(pattern)
            puts "✓ #{file} contains #{pattern}"
          else
            puts "✗ #{file} does NOT contain #{pattern}"
            all_updated = false
          end
        else
          puts "✗ #{file} does not exist"
          all_updated = false
        end
      end

      # Test idempotency - running again should skip files
      puts "  Testing idempotency..."
      result = run_command("cd #{original_dir} && bundle exec rake ecosystem:update_infrastructure[test_infra_eco]")

      if result[:success]
        if result[:stdout].include?("No changes were made") || result[:stdout].include?("already exists")
          puts "✓ Infrastructure update is idempotent"
        else
          puts "⚠ Infrastructure update may not be fully idempotent"
        end
      else
        puts "✗ Infrastructure update idempotency test failed"
        all_updated = false
      end

      # Clean up
      puts "  Cleaning up test artifacts..."
      run_command("cd #{original_dir} && git checkout -- .github bin script omnibus updater rakelib/support/helpers.rb")
      FileUtils.rm_rf("#{original_dir}/test_infra_eco")

      all_updated
    ensure
      FileUtils.rm_rf(test_dir)
      Dir.chdir(original_dir) if Dir.exist?(original_dir)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity

  def test_ecosystem_update_infrastructure_validates_name?
    puts "\n=== Testing ecosystem:update_infrastructure name validation ==="

    original_dir = Dir.pwd

    # Test with invalid name
    result = run_command("cd #{original_dir} && bundle exec rake ecosystem:update_infrastructure[Invalid-Name]")

    if result[:success]
      puts "✗ Should have failed with invalid ecosystem name"
      false
    elsif result[:stdout].include?("must start with a letter") || result[:stderr].include?("must start with a letter")
      puts "✓ Correctly validates ecosystem name format"
      true
    else
      puts "✗ Failed with unexpected error"
      puts "Output: #{result[:stdout]}"
      puts "STDERR: #{result[:stderr]}"
      false
    end
  end

  def test_ecosystem_update_infrastructure_requires_name?
    puts "\n=== Testing ecosystem:update_infrastructure requires name ==="

    original_dir = Dir.pwd

    # Test without name
    result = run_command("cd #{original_dir} && bundle exec rake ecosystem:update_infrastructure 2>&1")

    if result[:success]
      puts "✗ Should have failed without ecosystem name"
      false
    elsif result[:stdout].include?("Ecosystem name is required") ||
          result[:stderr].include?("Ecosystem name is required")
      puts "✓ Correctly requires ecosystem name"
      true
    else
      puts "✗ Failed with unexpected error"
      puts "Output: #{result[:stdout]}"
      puts "STDERR: #{result[:stderr]}"
      false
    end
  end

  # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
  def test_ecosystem_create?
    puts "\n=== Testing rake ecosystem:create ==="

    test_dir = Dir.mktmpdir
    original_dir = Dir.pwd

    begin
      # Test combined create task (scaffold + update_infrastructure)
      puts "  Running ecosystem:create..."
      result = run_command("cd #{original_dir} && bundle exec rake ecosystem:create[test_create_eco,skip]")

      unless result[:success]
        puts "✗ ecosystem:create FAILED to execute"
        puts "STDERR: #{result[:stderr]}"
        return false
      end

      Dir.chdir(original_dir)

      # Verify ecosystem was scaffolded
      ecosystem_files = [
        "test_create_eco/lib/dependabot/test_create_eco.rb",
        "test_create_eco/lib/dependabot/test_create_eco/file_fetcher.rb",
        "test_create_eco/README.md",
        "test_create_eco/dependabot-test_create_eco.gemspec"
      ]

      all_created = true
      ecosystem_files.each do |file|
        if File.exist?(file)
          puts "✓ #{file} was created"
        else
          puts "✗ #{file} was NOT created"
          all_created = false
        end
      end

      # Verify infrastructure was updated
      infra_files = {
        ".github/ci-filters.yml" => "test_create_eco",
        ".github/issue-labeler.yml" => "test_create_eco",
        "bin/dry-run.rb" => "test_create_eco",
        "omnibus/lib/dependabot/omnibus.rb" => "test_create_eco"
      }

      infra_files.each do |file, pattern|
        if File.exist?(file)
          content = File.read(file)
          if content.include?(pattern)
            puts "✓ #{file} contains #{pattern}"
          else
            puts "✗ #{file} does NOT contain #{pattern}"
            all_created = false
          end
        else
          puts "✗ #{file} does not exist"
          all_created = false
        end
      end

      # Clean up
      puts "  Cleaning up test artifacts..."
      run_command("cd #{original_dir} && git checkout -- .github bin script omnibus updater rakelib/support/helpers.rb")
      FileUtils.rm_rf("#{original_dir}/test_create_eco")

      all_created
    ensure
      FileUtils.rm_rf(test_dir)
      Dir.chdir(original_dir) if Dir.exist?(original_dir)
    end
  end
  # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

  def all_tests?
    results = []

    results << test_ecosystem_update_infrastructure_validates_name?
    results << test_ecosystem_update_infrastructure_requires_name?
    results << test_ecosystem_update_infrastructure?
    results << test_ecosystem_create?

    results.all?
  end
end
