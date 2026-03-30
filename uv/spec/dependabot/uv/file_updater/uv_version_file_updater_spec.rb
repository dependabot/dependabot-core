# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/file_updater/uv_version_file_updater"

RSpec.describe Dependabot::Uv::FileUpdater::UvVersionFileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: dependency_files
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "with a uv.toml containing an exact pin" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.7.0",
          requirements: [{
            file: "uv.toml",
            requirement: "==0.7.0",
            groups: ["uv-required-version"],
            source: nil
          }],
          previous_version: "0.6.12",
          previous_requirements: [{
            file: "uv.toml",
            requirement: "==0.6.12",
            groups: ["uv-required-version"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "updates the required-version field" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("uv.toml")
        expect(updated_files.first.content).to include('required-version = "==0.7.0"')
        expect(updated_files.first.content).not_to include("0.6.12")
      end
    end

    context "with a uv.toml containing a range constraint" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_range.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.7.0",
          requirements: [{
            file: "uv.toml",
            requirement: ">=0.7.0",
            groups: ["uv-required-version"],
            source: nil
          }],
          previous_version: nil,
          previous_requirements: [{
            file: "uv.toml",
            requirement: ">=0.6.0",
            groups: ["uv-required-version"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "updates the required-version field" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.content).to include('required-version = ">=0.7.0"')
        expect(updated_files.first.content).not_to include(">=0.6.0")
      end
    end

    context "with a pyproject.toml containing required-version under [tool.uv]" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "uv_required_version.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.7.0",
          requirements: [{
            file: "pyproject.toml",
            requirement: "==0.7.0",
            groups: ["uv-required-version"],
            source: nil
          }],
          previous_version: "0.6.12",
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: "==0.6.12",
            groups: ["uv-required-version"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "updates the required-version field in pyproject.toml" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("pyproject.toml")
        expect(updated_files.first.content).to include('required-version = "==0.7.0"')
        expect(updated_files.first.content).not_to include("0.6.12")
        # Ensure other content is preserved
        expect(updated_files.first.content).to include('name = "dependabot-uv"')
        expect(updated_files.first.content).to include("requests>=2.31.0")
      end
    end

    context "when the requirement hasn't changed" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.6.12",
          requirements: [{
            file: "uv.toml",
            requirement: "==0.6.12",
            groups: ["uv-required-version"],
            source: nil
          }],
          previous_version: "0.6.12",
          previous_requirements: [{
            file: "uv.toml",
            requirement: "==0.6.12",
            groups: ["uv-required-version"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "returns no updated files" do
        expect(updated_files).to be_empty
      end
    end

    context "when the dependency is not a uv tool dependency" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.32.0",
          requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.32.0",
            groups: ["dependencies"],
            source: nil
          }],
          previous_version: "2.31.0",
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.31.0",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "returns no updated files" do
        expect(updated_files).to be_empty
      end
    end

    context "with both uv.toml and pyproject.toml containing required-version" do
      let(:dependency_files) { [uv_toml, pyproject] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "uv_required_version.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.7.0",
          requirements: [
            {
              file: "uv.toml",
              requirement: "==0.7.0",
              groups: ["uv-required-version"],
              source: nil
            },
            {
              file: "pyproject.toml",
              requirement: "==0.7.0",
              groups: ["uv-required-version"],
              source: nil
            }
          ],
          previous_version: "0.6.12",
          previous_requirements: [
            {
              file: "uv.toml",
              requirement: "==0.6.12",
              groups: ["uv-required-version"],
              source: nil
            },
            {
              file: "pyproject.toml",
              requirement: "==0.6.12",
              groups: ["uv-required-version"],
              source: nil
            }
          ],
          package_manager: "uv"
        )
      end

      it "updates both files" do
        expect(updated_files.length).to eq(2)
        filenames = updated_files.map(&:name)
        expect(filenames).to contain_exactly("uv.toml", "pyproject.toml")

        uv_toml_updated = updated_files.find { |f| f.name == "uv.toml" }
        expect(uv_toml_updated.content).to include('required-version = "==0.7.0"')

        pyproject_updated = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproject_updated.content).to include('required-version = "==0.7.0"')
        expect(pyproject_updated.content).to include("requests>=2.31.0")
      end
    end

    context "with a pyproject.toml where another section has the same required-version" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "uv_required_version_with_collision.toml")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "uv",
          version: "0.7.0",
          requirements: [{
            file: "pyproject.toml",
            requirement: "==0.7.0",
            groups: ["uv-required-version"],
            source: nil
          }],
          previous_version: "0.6.12",
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: "==0.6.12",
            groups: ["uv-required-version"],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "only updates the [tool.uv] section, not [tool.other]" do
        expect(updated_files.length).to eq(1)
        content = updated_files.first.content
        # [tool.uv] section should be updated
        expect(content).to include("[tool.uv]\nrequired-version = \"==0.7.0\"")
        # [tool.other] section should be untouched
        expect(content).to include("[tool.other]\nrequired-version = \"==0.6.12\"")
      end
    end
  end
end
