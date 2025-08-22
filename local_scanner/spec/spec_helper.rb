# typed: false
# frozen_string_literal: true

require 'rspec'
require 'tempfile'
require 'fileutils'
require 'open3'
require 'json'
require 'yaml'
require 'benchmark'

# Add the lib directories to the load path for local testing
$LOAD_PATH.unshift(File.expand_path('../../common/lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../../bundler/lib', __dir__))
$LOAD_PATH.unshift(File.expand_path('../../updater/lib', __dir__))

# Load the local scanner
require_relative '../lib/dependabot/local_scanner'

module LocalScannerHelper
  def self.test_project_dir(project_name)
    File.expand_path("fixtures/projects/#{project_name}", __dir__)
  end

  def self.docker_image_name
    "ghcr.io/dependabot/dependabot-updater-local_scanner:latest"
  end

  def self.docker_available?
    # If we're inside a container (which we are when running tests), assume Docker is available
    return true if File.exist?('/.dockerenv')
    system("docker --version > /dev/null 2>&1")
  end

  def self.docker_image_exists?
    # If we're running inside the container, the image exists by definition
    return true if File.exist?('/.dockerenv')
    system("docker image inspect #{docker_image_name} > /dev/null 2>&1")
  end
end

RSpec.configure do |config|
  config.color = true
  config.order = :random
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.raise_errors_for_deprecations!
  config.example_status_persistence_file_path = ".rspec_status"

  config.before(:suite) do
    # Skip Docker tests if Docker is not available
    unless LocalScannerHelper.docker_available?
      puts "⚠️  Docker not available - skipping Docker integration tests"
    end

    # Skip Docker tests if custom image doesn't exist
    unless LocalScannerHelper.docker_image_exists?
      puts "⚠️  Local scanner Docker image not found - run script/build local_scanner first"
    end
  end

  config.around(:each) do |example|
    if example.metadata[:docker] && !LocalScannerHelper.docker_available?
      skip "Docker not available"
    elsif example.metadata[:docker] && !LocalScannerHelper.docker_image_exists?
      example.run
    else
      example.run
    end
  end
end
