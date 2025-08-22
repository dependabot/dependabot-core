# typed: false
# frozen_string_literal: true

require_relative "../../spec_helper"
require "open3"
require "json"

RSpec.describe Dependabot::LocalScanner::LocalDependabotScanner do
  let(:test_project_dir) { LocalScannerHelper.test_project_dir("basic_ruby_project") }
  let(:scanner) { described_class.new(test_project_dir) }

  describe "#initialize" do
    it "accepts a valid project path" do
      expect { described_class.new(test_project_dir) }.not_to raise_error
    end

    it "raises error for invalid project path" do
      expect { described_class.new("/nonexistent/path") }.to raise_error(ArgumentError)
    end

    it "raises error for project without Gemfile" do
      empty_dir = LocalScannerHelper.test_project_dir("empty_project")
      expect { described_class.new(empty_dir) }.to raise_error(ArgumentError)
    end
  end

  describe "#validate_project" do
    it "returns true for valid Ruby project" do
      expect(scanner.validate_project).to be true
    end

    it "raises error for invalid project" do
      invalid_scanner = described_class.new(LocalScannerHelper.test_project_dir("empty_project"))
      expect { invalid_scanner.validate_project }.to raise_error(ArgumentError)
    end
  end

  describe "#scan_dependencies" do
    it "returns dependency information" do
      result = scanner.scan_dependencies
      expect(result).to be_a(Hash)
      expect(result).to have_key("dependencies")
      expect(result["dependencies"]).to be_an(Array)
    end

    it "includes project path in result" do
      result = scanner.scan_dependencies
      expect(result["project_path"]).to eq(test_project_dir)
    end
  end

  describe "#scan_security_vulnerabilities" do
    it "returns security scan results" do
      result = scanner.scan_security_vulnerabilities
      expect(result).to be_a(Hash)
      expect(result).to have_key("security_scan")
      expect(result["security_scan"]).to have_key("vulnerabilities")
    end
  end

  describe "#generate_report" do
    it "generates summary format by default" do
      result = scanner.generate_report
      expect(result).to be_a(String)
      expect(result).to include("🔍 Scanning local Ruby project")
    end

    it "generates JSON format when requested" do
      result = scanner.generate_report(format: :json)
      expect { JSON.parse(result) }.not_to raise_error
      
      json_result = JSON.parse(result)
      expect(json_result).to have_key("scan_results")
    end

    it "generates text format when requested" do
      result = scanner.generate_report(format: :text)
      expect(result).to be_a(String)
      expect(result).to include("Project Path:")
    end
  end

  describe "error handling" do
    it "handles malformed Gemfile gracefully" do
      # Create a temporary malformed Gemfile
      temp_dir = Dir.mktmpdir("malformed_project")
      malformed_gemfile = File.join(temp_dir, "Gemfile")
      File.write(malformed_gemfile, "invalid ruby code here")

      expect { described_class.new(temp_dir) }.to raise_error(ArgumentError)
      
      FileUtils.remove_entry(temp_dir)
    end
  end
end

