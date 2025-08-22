# typed: false
# frozen_string_literal: true

require_relative "../../spec_helper"
require "open3"
require "json"

RSpec.describe "Local Scanner Docker Integration", :integration, :docker do
  let(:test_project_dir) { LocalScannerHelper.test_project_dir("basic_ruby_project") }
  let(:docker_image) { LocalScannerHelper.docker_image_name }

  describe "Docker container functionality" do
    it "can run the help command" do
      stdout, stderr, status = Open3.capture3("docker", "run", "--rm", docker_image, "--help")

      expect(status.success?).to be true
      expect(stdout).to include("Usage: ruby local_scan.rb [OPTIONS] PROJECT_PATH")
      expect(stderr).to be_empty
    end

    it "can scan a basic Ruby project" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{test_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🔍 Scanning local Ruby project")
      expect(stdout).to include("✅ Project validation passed")
      expect(stderr).to be_empty
    end

    it "can scan with JSON output format" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{test_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--output-format", "json", "/repo"
      )

      expect(status.success?).to be true

      # Verify JSON output is valid
      expect { JSON.parse(stdout) }.not_to raise_error

      # Verify JSON structure
      json_output = JSON.parse(stdout)
      expect(json_output).to have_key("scan_results")
      expect(json_output["scan_results"]).to have_key("project_path")
      expect(json_output["scan_results"]["project_path"]).to eq("/repo")
    end

    it "can scan with all-updates mode" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{test_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--all-updates", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🎯 Scan mode: All available updates")
      expect(stdout).to include("🎯 Scan complete!")
      expect(stderr).to be_empty
    end

    it "can scan with security-details mode" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{test_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🎯 Scan mode: Security vulnerabilities with detailed information")
      expect(stderr).to be_empty
    end

    it "handles missing project path gracefully" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb"
      )

      expect(status.success?).to be false
      expect(stderr).to include("Error: PROJECT_PATH is required")
    end

    it "handles invalid project path gracefully" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "/nonexistent/path"
      )

      expect(status.success?).to be false
      expect(stderr).to include("Error:")
    end
  end

  describe "Docker container performance" do
    it "starts up quickly" do
      start_time = Time.now
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--help"
      )
      end_time = Time.now

      startup_time = end_time - start_time
      expect(startup_time).to be < 5.0  # Should start in under 5 seconds
      expect(status.success?).to be true
    end

    it "handles multiple concurrent scans" do
      # Run multiple scans simultaneously
      processes = []
      3.times do
        processes << Open3.popen3(
          "docker", "run", "--rm",
          "-v", "#{test_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "/repo"
        )
      end

      # Wait for all processes to complete
      results = processes.map do |stdin, stdout, stderr, wait_thr|
        stdin.close
        output = stdout.read
        error = stderr.read
        status = wait_thr.value
        { output: output, error: error, status: status }
      end

      # All processes should succeed
      results.each do |result|
        expect(result[:status].success?).to be true
        expect(result[:error]).to be_empty
        expect(result[:output]).to include("🔍 Scanning local Ruby project")
      end
    end
  end
end
