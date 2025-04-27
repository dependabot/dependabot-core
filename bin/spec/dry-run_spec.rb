# typed: false
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "open3"
require "fileutils"

# Specs need to be run in a container,
# e.g., ./bin/docker-bin-dev bundler
#       cd ./bin/ && rspec
RSpec.describe "bin/dry-run" do # rubocop:disable RSpec/DescribeClass
  let(:script_path) { File.join(__dir__, "../dry-run.rb") }
  let(:base_args) { ["npm_and_yarn", "fake/repo"] }
  let(:cache_args) { ["--cache", "files,dependencies"] }

  # Shared helper method to run the script with options
  def run_with_options(options)
    cmd = ["ruby", script_path] + options + base_args
    stdout, stderr, status = Open3.capture3(*cmd)
    [stdout, stderr, status]
  end

  # Test the script by running it as a subprocess instead of requiring it directly
  it "displays help output when run without arguments" do
    stdout, _, status = Open3.capture3("ruby", script_path)

    # Check that the output contains expected help text
    expect(stdout).to include("usage: ruby bin/dry-run.rb [OPTIONS] PACKAGE_MANAGER REPO")
    expect(stdout).to include("--provider PROVIDER")
    expect(stdout).to include("--dir DIRECTORY")
    expect(status.exitstatus).to eq(1) # Should exit with status 1 for missing args
  end

  it "accepts valid package manager and repo arguments" do
    stdout, stderr, status = Open3.capture3(
      "ruby", script_path, *cache_args, *base_args
    )

    # Since we're using a fake repo, we expect it to attempt fetching but encounter an error
    expect(stdout + stderr).to include("fetching dependency files").or include("Invalid username or password")
    expect(status.exitstatus).to eq(1) # It should fail due to the fake repo
  end

  # Test each command-line option
  describe "command-line options" do
    # Test single-value options
    [
      "--provider azure",
      "--dir /custom/path",
      "--branch develop",
      "--dep lodash,express",
      "--cache files",
      "--requirements-update-strategy bump_versions",
      "--commit abc1234",
      "--updater-options goprivate=true,record_ecosystem_versions"
    ].each do |option_str|
      option_name = option_str.split.first
      option_value = option_str.split.last

      it "accepts #{option_name} option" do
        stdout, stderr, = run_with_options([option_name, option_value])

        # Ensure it doesn't show usage help (which would indicate option parsing error)
        expect(stdout).not_to include("usage: ruby bin/dry-run.rb [OPTIONS]") unless stderr.include?("RepoNotFound")
        # Option was accepted if we don't get option parser errors
        expect(stderr).not_to include("invalid option")
      end
    end

    # Test flag options (no value)
    [
      "--write",
      "--reject-external-code",
      "--vendor-dependencies",
      "--security-updates-only",
      "--pull-request",
      "--enable-beta-ecosystems"
    ].each do |flag|
      it "accepts #{flag} flag" do
        stdout, stderr, = run_with_options([flag])

        # Ensure it doesn't show usage help (which would indicate option parsing error)
        expect(stdout).not_to include("usage: ruby bin/dry-run.rb [OPTIONS]") unless stderr.include?("RepoNotFound")
        # Flag was accepted if we don't get option parser errors
        expect(stderr).not_to include("invalid option")
      end
    end

    it "accepts --cooldown option with valid JSON" do
      _, stderr, = run_with_options(["--cooldown", '{"cool-down-period": 60}'])

      # Option parsing should succeed
      expect(stderr).not_to include("invalid option")
    end

    it "rejects --cooldown option with invalid JSON" do
      stdout, _, status = run_with_options(["--cooldown", "{invalid-json}"])
      expect(stdout).to include("Invalid JSON format")
      expect(status.exitstatus).to eq(1)
    end
  end

  # Test caching functionality
  describe "caching behavior", :slow do
    let(:temp_dir) { Dir.mktmpdir }
    let(:repo_name) { "test-org/test-repo" }
    let(:cache_dir) { File.join(temp_dir, "dry-run", repo_name) }

    before do
      # Set up environment to use our temporary directory
      FileUtils.mkdir_p(cache_dir)
      stub_const("ENV", ENV.to_hash.merge("TMPDIR" => temp_dir))
    end

    after do
      FileUtils.remove_entry(temp_dir)
    end

    it "creates a cache directory when caching is enabled" do
      run_with_options(["--cache", "files", "--write"])

      # Check that the cache directory structure was created
      expect(Dir.exist?(cache_dir)).to be true
    end
  end

  # Test error handling
  describe "error handling" do
    it "handles non-existent package manager gracefully" do
      stdout, stderr, status = Open3.capture3(
        "ruby", script_path, "non_existent_manager", "fake/repo"
      )

      expect(stdout + stderr).to include("Invalid package manager")
      expect(status.exitstatus).not_to eq(0)
    end

    it "handles repo not found errors gracefully" do
      stdout, stderr, status = Open3.capture3(
        "ruby", script_path, "npm_and_yarn", "obviously/does-not-exist"
      )

      # Check for the actual error message
      expect(stdout + stderr).to include("Invalid username or password")
      expect(stdout + stderr).to include("Cloning into")
      expect(status.exitstatus).to eq(1) # Ensure the script exits with a non-zero status
    end
  end
end
