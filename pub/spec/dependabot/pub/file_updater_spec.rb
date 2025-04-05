# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/file_updater"
require "webrick"

require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Pub::FileUpdater do
  let(:project) { "can_update" }
  let(:dev_null) { WEBrick::Log.new("/dev/null", 7) }
  let(:server) { WEBrick::HTTPServer.new({ Port: 0, AccessLog: [], Logger: dev_null }) }
  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      # Simulate that the lockfile was from localhost:
      file.content.gsub!("https://pub.dartlang.org", "http://localhost:#{server[:Port]}")
    end
    files
  end
  let(:dependencies) { [dependency] }
  let(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: [{
        "type" => "hosted",
        "host" => "pub.dartlang.org",
        "username" => "x-access-token",
        "password" => "token"
      }],
      options: {
        pub_hosted_url: "http://localhost:#{server[:Port]}"
      }
    )
  end
  let(:sample) { "simple" }
  let(:sample_files) { Dir.glob(File.join("spec", "fixtures", "pub_dev_responses", sample, "*")) }

  after do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      server.unmount "/api/packages/#{package}"
    end
    server.shutdown
  end

  before do
    # Because we do the networking in dependency_services we have to run an
    # actual web server.
    Thread.new do
      server.start
    end
    sample_files.each do |f|
      package = File.basename(f, ".json")
      server.mount_proc "/api/packages/#{package}" do |_req, res|
        res.body = File.read(File.join("..", "..", "..", f))
      end
    end
  end

  it_behaves_like "a dependency file updater"

  def manifest(files)
    files.find { |f| f.name == "pubspec.yaml" }.content
  end

  def app_manifest(files)
    files.find { |f| f.name == "app/pubspec.yaml" }.content
  end

  def lockfile(files)
    files.find { |f| f.name == "pubspec.lock" }.content
  end

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "pubspec.yaml",
          "pubspec.lock",
          "packages/foo_bar/pubspec.yaml",
          "packages/foo_bar/pubspec.lock"
        ]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json",
          "Gemfile",
          "Gemfile.lock"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
  end

  describe "#updated_dependency_files unlock none" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "collection",
        version: "1.15.0",
        requirements: [],
        previous_version: "1.14.13",
        package_manager: "pub"
      )
    end

    it "updates pubspec.lock" do
      updated_files = updater.updated_dependency_files
      expect(manifest(updated_files)).to eq manifest(dependency_files)
      expect(lockfile(updated_files)).to include "version: \"1.15.0\""
    end
  end

  describe "#updated_dependency_files unlock none inserts content-locks when needed" do
    let(:project) { "can_update_content_hashes" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "collection",
        version: "1.15.0",
        requirements: [],
        previous_version: "1.14.13",
        package_manager: "pub"
      )
    end

    it "updates pubspec.lock, and updates the content-hash" do
      updated_files = updater.updated_dependency_files
      expect(manifest(updated_files)).to eq manifest(dependency_files)
      expect(lockfile(updated_files)).to include "version: \"1.15.0\""
      expect(lockfile(updated_files)).to include(
        "sha256: \"6d4193120997ecfd09acf0e313f13dc122b119e5eca87ef57a7d065ec9183762\""
      )
    end
  end

  describe "#updated_dependency_files unlock own" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "collection",
        version: "1.15.0",
        requirements: [{
          file: "pubspec.yaml",
          requirement: "^1.15.0",
          groups: ["direct"],
          source: nil
        }],
        previous_version: "1.14.13",
        previous_requirements: [{
          file: "pubspec.yaml",
          requirement: "^1.14.13",
          groups: ["direct"],
          source: nil
        }],
        package_manager: "pub"
      )
    end

    it "updates pubspec.lock" do
      updated_files = updater.updated_dependency_files
      expect(manifest(updated_files)).to include "collection: ^1.15.0"
      expect(lockfile(updated_files)).to include "version: \"1.15.0\""
    end
  end

  describe "Updates sub-project in pub workspace" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "pub_semver",
          version: "2.1.4",
          requirements: [{
            file: "pubspec.yaml",
            requirement: "^2.1.4",
            groups: ["direct"],
            source: nil
          }],
          previous_version: "2.0.0",
          previous_requirements: [{
            file: "pubspec.yaml",
            requirement: "^2.0.0",
            groups: ["direct"],
            source: nil
          }],
          package_manager: "pub"
        ),
        Dependabot::Dependency.new(
          name: "meta",
          version: "1.15.0",
          requirements: [{
            file: "pubspec.yaml",
            requirement: "^1.15.0",
            groups: ["direct"],
            source: nil
          }],
          previous_version: "1.3.0-nullsafety.6",
          previous_requirements: [{
            file: "pubspec.yaml",
            requirement: "^1.3.0-nullsafety.6",
            groups: ["direct"],
            source: nil
          }],
          package_manager: "pub"
        )
      ]
    end

    it "updates pubspec.lock" do
      updated_files = updater.updated_dependency_files
      expect(manifest(updated_files)).to include "pub_semver: ^2.1.4"
      expect(lockfile(updated_files)).to include "version: \"2.1.4\""
      expect(manifest(updated_files)).to include "meta: ^1.15.0"
      expect(lockfile(updated_files)).to include "version: \"1.15.0\""
    end
  end

  describe "#updated_dependency_files unlock all" do
    let(:project) { "can_update_workspace" }
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "meta",
          version: "1.7.0",
          requirements: [{
            file: "pubspec.yaml",
            requirement: "1.7.0",
            groups: ["direct"],
            source: nil
          }],
          previous_version: "1.6.0",
          previous_requirements: [{
            file: "pubspec.yaml",
            requirement: "1.7.0",
            groups: ["direct"],
            source: nil
          }],
          package_manager: "pub"
        )
      ]
    end

    it "updates pubspec.lock" do
      updated_files = updater.updated_dependency_files
      expect(app_manifest(updated_files)).to include "meta: 1.7.0"
      expect(lockfile(updated_files)).to include "version: \"1.7.0\""
    end
  end
end
