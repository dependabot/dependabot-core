# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/swift/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Swift::FileUpdater do
  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  it_behaves_like "a dependency file updater"

  let(:project_name) { "Example" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:files) { project_dependency_files(project_name) }
  let(:dependencies) { [] }
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  describe "#updated_dependency_files" do
    subject { updater.updated_dependency_files }

    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "github.com/reactivecocoa/reactiveswift",
          version: "7.1.1",
          previous_version: "7.1.0",
          requirements: [{
            requirement: "= 7.1.1",
            groups: [],
            file: "Package.swift",
            source: {
              type: "git",
              url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
              ref: "7.1.0",
              branch: nil
            },
            metadata: {
              requirement_string: "exact: \"7.1.1\""
            }
          }],
          previous_requirements: [{
            requirement: "= 7.1.0",
            groups: [],
            file: "Package.swift",
            source: {
              type: "git",
              url: "https://github.com/ReactiveCocoa/ReactiveSwift.git",
              ref: "7.1.0",
              branch: nil
            },
            metadata: {
              declaration_string:
                ".package(url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.0\")",
              requirement_string: "exact: \"7.1.0\""
            }
          }],
          package_manager: "swift",
          metadata: { identity: "reactiveswift" }
        )
      ]
    end

    it "updates the version in manifest and lockfile" do
      manifest = subject.find { |file| file.name == "Package.swift" }

      expect(manifest.content).to include(
        "url: \"https://github.com/ReactiveCocoa/ReactiveSwift.git\",\n             exact: \"7.1.1\""
      )

      lockfile = subject.find { |file| file.name == "Package.resolved" }

      expect(lockfile.content.gsub(/^ {4}/, "")).to include <<~RESOLVED
        {
          "identity" : "reactiveswift",
          "kind" : "remoteSourceControl",
          "location" : "https://github.com/ReactiveCocoa/ReactiveSwift.git",
          "state" : {
            "revision" : "40c465af19b993344e84355c00669ba2022ca3cd",
            "version" : "7.1.1"
          }
        },
      RESOLVED
    end

    context "when latest version is higher than target version" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/apple/swift-docc-plugin",
            version: "1.1.0",
            previous_version: "1.0.0",
            requirements: [{
              requirement: ">= 1.1.0, < 2.0.0",
              groups: [],
              file: "Package.swift",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-docc-plugin",
                ref: "1.0.0",
                branch: nil
              },
              metadata: {
                requirement_string: "from: \"1.1.0\""
              }
            }],
            previous_requirements: [{
              requirement: ">= 1.0.0, < 2.0.0",
              groups: [],
              file: "Package.swift",
              source: {
                type: "git",
                url: "https://github.com/apple/swift-docc-plugin",
                ref: "1.0.0",
                branch: nil
              },
              metadata: {
                declaration_string:
                  ".package(\n      url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.0.0\")",
                requirement_string: "from: \"1.0.0\""
              }
            }],
            package_manager: "swift",
            metadata: { identity: "swift-docc-plugin" }
          )
        ]
      end

      it "properly updates to target version in manifest and lockfile" do
        manifest = subject.find { |file| file.name == "Package.swift" }

        expect(manifest.content).to include(
          "url: \"https://github.com/apple/swift-docc-plugin\",\n      from: \"1.1.0\""
        )

        lockfile = subject.find { |file| file.name == "Package.resolved" }

        expect(lockfile.content.gsub(/^ {4}/, "")).to include <<~RESOLVED
          {
            "identity" : "swift-docc-plugin",
            "kind" : "remoteSourceControl",
            "location" : "https://github.com/apple/swift-docc-plugin",
            "state" : {
              "revision" : "10bc670db657d11bdd561e07de30a9041311b2b1",
              "version" : "1.1.0"
            }
          },
        RESOLVED
      end
    end
  end
end
