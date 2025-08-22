# typed: false
# frozen_string_literal: true

require_relative "../../spec_helper"
require "yaml"
require "json"

RSpec.describe "Local Scanner Security Features", :security, :docker do
  let(:basic_project_dir) { LocalScannerHelper.test_project_dir("basic_ruby_project") }
  let(:vulnerable_project_dir) { LocalScannerHelper.test_project_dir("vulnerable_project") }
  let(:docker_image) { LocalScannerHelper.docker_image_name }

  describe "security vulnerability detection" do
    it "detects known vulnerable dependencies" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🔒 Security vulnerabilities detected")
      expect(stderr).to be_empty
    end

    it "provides detailed vulnerability information" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      
      # Should include CVE information
      expect(stdout).to include("CVE-")
      expect(stdout).to include("Severity:")
      expect(stdout).to include("Description:")
    end

    it "generates JSON security report" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--output-format", "json", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      expect { JSON.parse(stdout) }.not_to raise_error

      json_result = JSON.parse(stdout)
      expect(json_result).to have_key("scan_results")
      expect(json_result["scan_results"]).to have_key("security_scan")
      expect(json_result["scan_results"]["security_scan"]).to have_key("vulnerabilities")
    end
  end

  describe "Ruby Advisory Database integration" do
    it "loads advisory database correctly" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      # Should not show advisory database loading errors
      expect(stderr).not_to include("advisory")
      expect(stderr).not_to include("database")
    end

    it "provides accurate CVE information" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      
      # Should show actual CVE IDs (not placeholder text)
      expect(stdout).to match(/CVE-\d{4}-\d+/)
    end
  end

  describe "bundle audit integration" do
    it "runs bundle audit when available" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      
      # Should show bundle audit results or indicate it's not available
      expect(stdout).to match(/bundle audit|Bundle audit not available/)
    end
  end

  describe "false positive handling" do
    it "does not report false positives on secure dependencies" do
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{basic_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      
      # Should not report vulnerabilities for secure project
      expect(stdout).not_to include("🔒 Security vulnerabilities detected")
      expect(stdout).to include("✅ No security vulnerabilities found")
    end
  end

  describe "security scan modes" do
    it "provides different security detail levels" do
      # Basic security scan
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🔒 Security vulnerabilities detected")

      # Detailed security scan
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      expect(stdout).to include("🔒 Security vulnerabilities detected")
      # Detailed scan should show more information
      expect(stdout).to include("Description:")
    end
  end

  describe "security scan performance" do
    it "completes security scan within reasonable time" do
      time = Benchmark.realtime do
        stdout, stderr, status = Open3.capture3(
          "docker", "run", "--rm",
          "-v", "#{vulnerable_project_dir}:/repo",
          docker_image,
          "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
        )
        expect(status.success?).to be true
      end

      # Security scan should complete in reasonable time
      expect(time).to be < 30.0
    end
  end

  describe "error handling in security scans" do
    it "handles advisory database errors gracefully" do
      # This test would require mocking the advisory database to be unavailable
      # For now, we test that the scanner doesn't crash on security scan
      stdout, stderr, status = Open3.capture3(
        "docker", "run", "--rm",
        "-v", "#{vulnerable_project_dir}:/repo",
        docker_image,
        "ruby", "bin/local_ruby_scan.rb", "--security-details", "/repo"
      )

      expect(status.success?).to be true
      # Should complete scan even if there are advisory database issues
      expect(stdout).to include("🎯 Scan complete!")
    end
  end
end
