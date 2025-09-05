# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/vcpkg/file_updater"

RSpec.describe Dependabot::Vcpkg::FileUpdater do
  let(:dependency_files) { [vcpkg_json] }
  let(:vcpkg_json) do
    Dependabot::DependencyFile.new(
      name: "vcpkg.json",
      content: vcpkg_json_content
    )
  end
  let(:vcpkg_json_content) do
    <<~JSON
      {
        "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
        "builtin-baseline": "old-commit-sha",
        "dependencies": [
          "fmt",
          "ms-gsl"
        ]
      }
    JSON
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/microsoft/vcpkg",
      version: "new-commit-sha",
      previous_version: "old-commit-sha",
      requirements: [{
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/vcpkg.git",
          ref: "new-commit-sha"
        },
        file: "vcpkg.json"
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/vcpkg.git",
          ref: "old-commit-sha"
        },
        file: "vcpkg.json"
      }],
      package_manager: "vcpkg"
    )
  end

  let(:dependencies) { [dependency] }
  let(:credentials) { [] }

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: credentials
    )
  end

  describe ".updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "matches vcpkg.json files" do
      expect(updated_files_regex).to include(match("vcpkg.json"))
      expect(updated_files_regex).to include(match("path/to/vcpkg.json"))
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) { updater.updated_dependency_files }

    context "when the vcpkg.json file needs updating" do
      it "returns the updated vcpkg.json file" do
        expect(updated_dependency_files.length).to eq(1)

        updated_file = updated_dependency_files.first
        expect(updated_file.name).to eq("vcpkg.json")

        updated_content = JSON.parse(updated_file.content)
        expect(updated_content["builtin-baseline"]).to eq("new-commit-sha")
        expect(updated_content["dependencies"]).to eq(%w(fmt ms-gsl))
        expect(updated_content["$schema"]).to eq("https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json")
      end
    end

    context "when the dependency doesn't affect the vcpkg.json file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "some-other-dependency",
          version: "1.0.0",
          previous_version: "0.9.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "vcpkg"
        )
      end

      it "returns no updated files" do
        expect(updated_dependency_files).to be_empty
      end
    end

    context "when the vcpkg.json has invalid JSON" do
      let(:vcpkg_json_content) { "{ invalid json" }

      it "raises a DependencyFileNotParseable error" do
        expect { updated_dependency_files }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when vcpkg.json is missing" do
      let(:dependency_files) { [] }

      it "raises a DependencyFileNotFound error" do
        expect { updater }.to raise_error(Dependabot::DependencyFileNotFound, "vcpkg.json not found")
      end
    end

    context "when updating builtin-baseline preserves file formatting" do
      let(:vcpkg_json_content) do
        <<~JSON
          {
            "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
            "name": "my-project",
            "version": "1.0.0",
            "builtin-baseline": "old-commit-sha",
            "dependencies": [
              "fmt",
              {
                "name": "boost-system",
                "features": ["threading"]
              }
            ]
          }
        JSON
      end

      it "preserves all other properties and structure" do
        updated_file = updated_dependency_files.first
        updated_content = JSON.parse(updated_file.content)

        expect(updated_content["builtin-baseline"]).to eq("new-commit-sha")
        expect(updated_content["name"]).to eq("my-project")
        expect(updated_content["version"]).to eq("1.0.0")
        expect(updated_content["dependencies"]).to eq([
          "fmt",
          { "name" => "boost-system", "features" => ["threading"] }
        ])
      end
    end

    context "when there are multiple requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "github.com/microsoft/vcpkg",
          version: "new-commit-sha",
          previous_version: "old-commit-sha",
          requirements: [
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "new-commit-sha"
              },
              file: "vcpkg.json"
            },
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "new-commit-sha"
              },
              file: "other-file.json"
            }
          ],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "old-commit-sha"
              },
              file: "vcpkg.json"
            },
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "old-commit-sha"
              },
              file: "other-file.json"
            }
          ],
          package_manager: "vcpkg"
        )
      end

      it "only updates the vcpkg.json file" do
        expect(updated_dependency_files.length).to eq(1)

        updated_file = updated_dependency_files.first
        expect(updated_file.name).to eq("vcpkg.json")

        updated_content = JSON.parse(updated_file.content)
        expect(updated_content["builtin-baseline"]).to eq("new-commit-sha")
      end
    end
  end

  describe "#updated_dependency_files for port dependencies" do
    subject(:updated_dependency_files) { updater.updated_dependency_files }

    let(:vcpkg_json_content) do
      <<~JSON
        {
          "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
          "name": "my-project",
          "version": "1.0.0",
          "dependencies": [
            {
              "name": "curl",
              "version>=": "8.10.0"
            },
            {
              "name": "boost-system",
              "version>=": "1.82.0"
            }
          ]
        }
      JSON
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "curl",
        version: "8.15.0#1",
        previous_version: "8.10.0",
        requirements: [{
          requirement: ">=8.15.0#1",
          groups: [],
          source: nil,
          file: "vcpkg.json"
        }],
        previous_requirements: [{
          requirement: ">=8.10.0",
          groups: [],
          source: nil,
          file: "vcpkg.json"
        }],
        package_manager: "vcpkg"
      )
    end

    it "updates the version constraint for the port dependency" do
      updated_file = updated_dependency_files.first
      updated_content = JSON.parse(updated_file.content)

      curl_dep = updated_content["dependencies"].find { |dep| dep["name"] == "curl" }
      expect(curl_dep["version>="]).to eq("8.15.0#1")

      # Verify other dependencies are unchanged
      boost_dep = updated_content["dependencies"].find { |dep| dep["name"] == "boost-system" }
      expect(boost_dep["version>="]).to eq("1.82.0")
    end

    it "preserves all other properties and structure" do
      updated_file = updated_dependency_files.first
      updated_content = JSON.parse(updated_file.content)

      expect(updated_content["name"]).to eq("my-project")
      expect(updated_content["version"]).to eq("1.0.0")
      expect(updated_content["$schema"]).to eq("https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json")
    end

    context "with multiple port dependencies updating" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "curl",
            version: "8.15.0#1",
            previous_version: "8.10.0",
            requirements: [{
              requirement: ">=8.15.0#1",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            previous_requirements: [{
              requirement: ">=8.10.0",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            package_manager: "vcpkg"
          ),
          Dependabot::Dependency.new(
            name: "boost-system",
            version: "1.84.0",
            previous_version: "1.82.0",
            requirements: [{
              requirement: ">=1.84.0",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            previous_requirements: [{
              requirement: ">=1.82.0",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            package_manager: "vcpkg"
          )
        ]
      end

      it "updates all port dependencies" do
        updated_file = updated_dependency_files.first
        updated_content = JSON.parse(updated_file.content)

        curl_dep = updated_content["dependencies"].find { |dep| dep["name"] == "curl" }
        expect(curl_dep["version>="]).to eq("8.15.0#1")

        boost_dep = updated_content["dependencies"].find { |dep| dep["name"] == "boost-system" }
        expect(boost_dep["version>="]).to eq("1.84.0")
      end
    end

    context "with mixed baseline and port dependency updates" do
      let(:vcpkg_json_content) do
        <<~JSON
          {
            "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
            "name": "my-project",
            "version": "1.0.0",
            "builtin-baseline": "old-commit-sha",
            "dependencies": [
              {
                "name": "curl",
                "version>=": "8.10.0"
              }
            ]
          }
        JSON
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/microsoft/vcpkg",
            version: "new-commit-sha",
            previous_version: "old-commit-sha",
            requirements: [{
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "new-commit-sha"
              },
              file: "vcpkg.json"
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: "old-commit-sha"
              },
              file: "vcpkg.json"
            }],
            package_manager: "vcpkg"
          ),
          Dependabot::Dependency.new(
            name: "curl",
            version: "8.15.0#1",
            previous_version: "8.10.0",
            requirements: [{
              requirement: ">=8.15.0#1",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            previous_requirements: [{
              requirement: ">=8.10.0",
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            package_manager: "vcpkg"
          )
        ]
      end

      it "updates both baseline and port dependencies" do
        updated_file = updated_dependency_files.first
        updated_content = JSON.parse(updated_file.content)

        expect(updated_content["builtin-baseline"]).to eq("new-commit-sha")

        curl_dep = updated_content["dependencies"].find { |dep| dep["name"] == "curl" }
        expect(curl_dep["version>="]).to eq("8.15.0#1")
      end
    end
  end
end
