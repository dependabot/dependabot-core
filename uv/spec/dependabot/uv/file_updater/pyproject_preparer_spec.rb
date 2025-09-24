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

  describe "#add_auth_env_vars" do
    it "adds auth env vars when a token is present" do
      preparer.add_auth_env_vars(
        [
          {
            "type" => "python_index",
            "index-url" => "some.internal.registry.com/pypi/",
            "token" => "hello:world"
          }
        ]
      )
      expect(ENV.delete("UV_INDEX_URL_TOKEN_SOME_INTERNAL_REGISTRY_COM_PYPI_")).to eq("hello:world")
      expect(ENV.delete("PIP_INDEX_URL")).to eq("https://hello:world@some.internal.registry.com/pypi/")
    end

    it "has no effect when a token is not present" do
      preparer.add_auth_env_vars(
        [
          {
            "index-url" => "https://some.internal.registry.com/pypi/"
          }
        ]
      )
      expect(ENV.fetch("UV_INDEX_URL_TOKEN_SOME_INTERNAL_REGISTRY_COM_PYPI_", nil)).to be_nil
    end

    it "doesn't break when there are no credentials" do
      expect { preparer.add_auth_env_vars(nil) }.not_to raise_error
    end
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
