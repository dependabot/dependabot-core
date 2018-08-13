# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pyproject_preparer"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PyprojectPreparer do
  let(:preparer) { described_class.new(pyproject_content: pyproject_content) }
  let(:pyproject_content) do
    fixture("python", "pyproject_files", "pyproject.toml")
  end

  describe "#replace_sources" do
    subject(:replace_sources) { preparer.replace_sources(credentials) }

    context "with no credentials" do
      let(:credentials) { [] }
      it { is_expected.to_not include("tool.poetry.source") }
    end

    context "with a python_index credential" do
      let(:credentials) do
        [{
          "type" => "python_index",
          "index-url" => "https://username:password@pypi.posrip.com/pypi/"
        }]
      end

      it { is_expected.to include("tool.poetry.source") }
      it { is_expected.to include('url = "https://username:password@pypi') }
    end
  end

  describe "#freeze_top_level_dependencies_except" do
    subject(:freeze_top_level_dependencies_except) do
      preparer.freeze_top_level_dependencies_except(dependencies, lockfile)
    end

    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "pyproject.lock",
        content: pyproject_lock_body
      )
    end
    let(:pyproject_lock_body) do
      fixture("python", "pyproject_locks", pyproject_lock_fixture_name)
    end
    let(:pyproject_lock_fixture_name) { "pyproject.lock" }

    context "with no dependencies to except" do
      let(:dependencies) { [] }
      it { is_expected.to include("geopy = \"1.14.0\"\n") }
      it { is_expected.to include("hypothesis = \"3.57.0\"\n") }
      it { is_expected.to include("python = \"^3.6\"\n") }
    end

    context "with a dependency to except" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "geopy",
            version: "1.14.0",
            package_manager: "pip",
            requirements: []
          )
        ]
      end

      it { is_expected.to include("geopy = \"^1.13\"\n") }
    end
  end
end
