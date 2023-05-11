# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/file_updater"
require "webrick"

require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Pub::FileUpdater do
  it_behaves_like "a dependency file updater"

  before(:all) do
    # Because we do the networking in dependency_services we have to run an
    # actual web server.
    dev_null = WEBrick::Log.new("/dev/null", 7)
    @server = WEBrick::HTTPServer.new({ Port: 0, AccessLog: [], Logger: dev_null })
    Thread.new do
      @server.start
    end
  end

  after(:all) do
    @server.shutdown
  end

  before do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      @server.mount_proc "/api/packages/#{package}" do |_req, res|
        res.body = File.read(File.join("..", "..", f))
      end
    end
  end

  after do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      @server.unmount "/api/packages/#{package}"
    end
  end

  let(:sample_files) { Dir.glob(File.join("spec", "fixtures", "pub_dev_responses", sample, "*")) }
  let(:sample) { "simple" }

  def manifest(files)
    files.find { |f| f.name == "pubspec.yaml" }.content
  end

  def lockfile(files)
    files.find { |f| f.name == "pubspec.lock" }.content
  end

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
        pub_hosted_url: "http://localhost:#{@server[:Port]}"
      }
    )
  end

  let(:dependencies) { [dependency] }

  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      # Simulate that the lockfile was from localhost:
      file.content.gsub!("https://pub.dartlang.org", "http://localhost:#{@server[:Port]}")
    end
    files
  end
  let(:project) { "can_update" }

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

  describe "#updated_dependency_files unlock all" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "protobuf",
          version: "2.0.0",
          requirements: [{
            file: "pubspec.yaml",
            requirement: "^2.0.0",
            groups: ["direct"],
            source: nil
          }],
          previous_version: "1.1.4",
          previous_requirements: [{
            file: "pubspec.yaml",
            requirement: "^1.1.4",
            groups: ["direct"],
            source: nil
          }],
          package_manager: "pub"
        ),
        Dependabot::Dependency.new(
          name: "fixnum",
          version: "1.0.0",
          requirements: [{
            file: "pubspec.yaml",
            requirement: "^1.0.0",
            groups: ["direct"],
            source: nil
          }],
          previous_version: "0.10.11",
          previous_requirements: [{
            file: "pubspec.yaml",
            requirement: "^0.10.11",
            groups: ["direct"],
            source: nil
          }],
          package_manager: "pub"
        )
      ]
    end
    it "updates pubspec.lock" do
      updated_files = updater.updated_dependency_files
      expect(manifest(updated_files)).to include "protobuf: ^2.0.0"
      expect(lockfile(updated_files)).to include "version: \"2.0.0\""
      expect(manifest(updated_files)).to include "fixnum: ^1.0.0"
      expect(lockfile(updated_files)).to include "version: \"1.0.0\""
    end
  end
end
