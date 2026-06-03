# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/file_updater/pyproject_preparer"

RSpec.describe Dependabot::Uv::FileUpdater::PyprojectPreparer do
  let(:preparer) do
    described_class.new(pyproject_content: pyproject_content, lockfile: lockfile)
  end

  let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }
  let(:lockfile_content) { fixture("uv_locks", "simple.lock") }

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "uv.lock",
      content: lockfile_content
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.26.0",
      requirements: [{
        file: "pyproject.toml",
        requirement: ">=2.26.0",
        groups: [],
        source: nil
      }],
      previous_version: "2.32.3",
      previous_requirements: [{
        file: "pyproject.toml",
        requirement: ">=2.31.0",
        groups: [],
        source: nil
      }],
      package_manager: "uv"
    )
  end

  describe "#sanitize" do
    subject(:sanitized_content) { preparer.sanitize }

    it "returns the pyproject content unchanged" do
      expect(sanitized_content).to eq(pyproject_content)
    end
  end

  describe "#update_python_requirement" do
    subject(:updated_content) { preparer.update_python_requirement("3.10") }

    it "updates the Python requirement" do
      expect(updated_content).to include('requires-python = ">=3.10"')
    end

    context "when no python version is provided" do
      subject(:updated_content) { preparer.update_python_requirement(nil) }

      it "leaves the Python requirement unchanged" do
        expect(updated_content).to include('requires-python = ">=3.9"')
      end
    end

    context "when pyproject has no python requirement" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "sample-project"
          version = "0.1.0"
          dependencies = [
              "requests>=2.22.0",
          ]
        TOML
      end

      it "doesn't add a python requirement" do
        expect(updated_content).not_to include("requires-python")
      end
    end
  end
end
