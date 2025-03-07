# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/pub/helpers"
require "fileutils"

RSpec.describe Dependabot::Pub::Helpers do
  let(:dummy_class) do
    Class.new do
      include Dependabot::Pub::Helpers

      def initialize(credentials:, dependency_files:, options: {})
        @credentials = credentials
        @dependency_files = dependency_files
        @options = options
      end
    end
  end

  let(:credentials) { [{ "type" => "hosted", "host" => "pub.dartlang.org" }] }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(name: "pubspec.yaml", content: "name: example_project"),
      Dependabot::DependencyFile.new(name: "pubspec.lock", content: "packages: {}")
    ]
  end
  let(:options) { {} }
  let(:helpers) { dummy_class.new(credentials: credentials, dependency_files: dependency_files, options: options) }

  before do
    # Mocking Flutter clone operation to always succeed
    allow(Open3).to receive(:capture3).with(
      {}, "git", "clone", "--no-checkout", "https://github.com/flutter/flutter", chdir: "/tmp/"
    ).and_return(["", "", instance_double(Process::Status, success?: true)])

    allow(Open3).to receive(:capture3).with(
      {}, "git", "fetch", "origin", anything, chdir: "/tmp/flutter"
    ).and_return(["", "", instance_double(Process::Status, success?: true)])

    allow(Open3).to receive(:capture3).with(
      {}, "git", "checkout", anything, chdir: "/tmp/flutter"
    ).and_return(["", "", instance_double(Process::Status, success?: true)])

    flutter_version_mock_output = {
      "frameworkVersion" => "3.29.1",
      "dartSdkVersion" => "3.7.0"
    }.to_json

    allow(Open3).to receive(:capture3).with(
      anything, # Match any environment variables
      "/tmp/flutter/bin/flutter", "--version", "--machine",
      hash_including(chdir: anything) # Match chdir values properly
    ).and_return([
      flutter_version_mock_output, "", instance_double(Process::Status, success?: true)
    ])
  end

  describe "#find_workspace_root" do
    let(:temp_dir) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(temp_dir, "packages/subpackage"))
      File.write(File.join(temp_dir, "pubspec.yaml"), "")
      File.write(File.join(temp_dir, "pubspec.lock"), "")
      File.write(File.join(temp_dir, "packages/subpackage/pubspec.yaml"), "")
    end

    after { FileUtils.remove_entry(temp_dir) }

    it "detects the workspace root when a pubspec.lock file is present" do
      detected_root = helpers.send(:find_workspace_root, File.join(temp_dir, "packages/subpackage"))
      expect(detected_root).to eq(temp_dir)
    end
  end

  describe "#run_dependency_services" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:command) { "list" }

    before do
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield(temp_dir)
      allow(helpers).to receive(:find_workspace_root).and_return(temp_dir)
      allow(Open3).to receive(:capture3).and_return(["{}", "", instance_double(Process::Status, success?: true)])
    end

    after { FileUtils.remove_entry(temp_dir) }

    it "executes dependency_services in the correct directory" do
      expect(Open3).to receive(:capture3).with(
        hash_including("PUB_ENVIRONMENT" => "dependabot"),
        File.join(described_class.pub_helpers_path, "dependency_services"),
        command,
        stdin_data: nil,
        chdir: temp_dir
      )
      helpers.send(:run_dependency_services, command)
    end

    it "raises an error if dependency_services fails" do
      allow(Open3).to receive(:capture3).and_return(
        ["", "Dependency error", instance_double(Process::Status, success?: false)]
      )
      expect do
        helpers.send(:run_dependency_services, command)
      end.to raise_error(Dependabot::DependabotError, "dependency_services failed: Dependency error")
    end
  end

  describe "#run_flutter_version" do
    it "returns Flutter and Dart versions" do
      versions = helpers.send(:run_flutter_version)
      expect(versions).to eq({ "flutter" => "3.29.1", "dart" => "3.7.0" })
    end
  end

  describe "#raise_error" do
    it "raises a specific error for failed parsing of lock file" do
      expect do
        helpers.send(:raise_error, "Failed parsing lock file")
      end.to raise_error(Dependabot::DependencyFileNotEvaluatable, /dependency_services failed/)
    end

    it "raises a specific error for Git authentication issues" do
      expect do
        helpers.send(:raise_error, "Git error")
      end.to raise_error(Dependabot::InvalidGitAuthToken, /dependency_services failed/)
    end

    it "raises a specific error for dependency resolution issues" do
      expect do
        helpers.send(:raise_error, "version solving failed")
      end.to raise_error(Dependabot::DependencyFileNotResolvable, /dependency_services failed/)
    end

    it "raises a generic Dependabot error for unknown issues" do
      expect do
        helpers.send(:raise_error, "Some other error")
      end.to raise_error(Dependabot::DependabotError, /dependency_services failed/)
    end
  end
end
