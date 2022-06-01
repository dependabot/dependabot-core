# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pyproject_preparer"

RSpec.describe Dependabot::Python::FileUpdater::PyprojectPreparer do
  let(:preparer) do
    described_class.new(
      pyproject_content: pyproject_content,
      lockfile: lockfile
    )
  end
  let(:lockfile) { nil }
  let(:pyproject_content) { fixture("pyproject_files", pyproject_fixture_name) }
  let(:pyproject_fixture_name) { "pyproject.toml" }

  describe "#sanitize" do
    subject(:sanitized_content) { preparer.sanitize }

    context "with a pyproject that doesn't need sanitizing" do
      it { is_expected.to eq(pyproject_content) }
    end

    context "with a pyproject that has a {{ name }} variable" do
      let(:pyproject_content) do
        fixture("pyproject_files", "needs_sanitization.toml")
      end

      it "replaces the {{ name }} variable" do
        expect(sanitized_content).to include('name = "something"')
      end

      it "replaces the # symbol" do
        expect(sanitized_content).to include("Various {small} python projects.")
      end
    end
  end

  describe "#freeze_top_level_dependencies_except" do
    subject(:freeze_top_level_dependencies_except) do
      preparer.freeze_top_level_dependencies_except(dependencies)
    end

    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "pyproject.lock",
        content: pyproject_lock_body
      )
    end
    let(:pyproject_lock_body) do
      fixture("pyproject_locks", pyproject_lock_fixture_name)
    end
    let(:pyproject_lock_fixture_name) { "pyproject.lock" }

    context "with no dependencies to except" do
      let(:dependencies) { [] }
      it { is_expected.to include("geopy = \"1.14.0\"\n") }
      it { is_expected.to include("hypothesis = \"3.57.0\"\n") }
      it { is_expected.to include("python = \"^3.6 || ^3.7\"\n") }

      context "with extras" do
        let(:pyproject_fixture_name) { "extras.toml" }
        let(:pyproject_lock_fixture_name) { "extras.lock" }

        it "preserves details of the extras" do
          expect(freeze_top_level_dependencies_except).to include(
            "[tool.poetry.dependencies.celery]\n"\
            "extras = [\"redis\"]\n"\
            "version = \"4.3.0\"\n"
          )
        end
      end
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

    context "with directory dependency" do
      let(:dependencies) { [] }

      let(:pyproject_lock_fixture_name) { "dir_dependency.lock" }
      let(:pyproject_fixture_name) { "dir_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }
      it "does not include the version for path deps" do
        expect(freeze_top_level_dependencies_except).to_not include(
          "path = \"../toml\"\n"\
          "version = \"0.10.0\"\n"
        )
        expect(freeze_top_level_dependencies_except).to include(
          "path = \"../toml\"\n"
        )
      end
    end

    context "with file dependency" do
      let(:dependencies) { [] }

      let(:pyproject_lock_fixture_name) { "file_dependency.lock" }
      let(:pyproject_fixture_name) { "file_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }
      it "does not include the version for path deps" do
        expect(freeze_top_level_dependencies_except).to_not include(
          "path = \"toml-8.2.54.tar.gz\"\n"\
          "version = \"8.2.54\"\n"
        )
        expect(freeze_top_level_dependencies_except).to include(
          "path = \"toml-8.2.54.tar.gz\"\n"
        )
      end
    end

    context "with url dependency" do
      let(:dependencies) { [] }

      let(:pyproject_lock_fixture_name) { "url_dependency.lock" }
      let(:pyproject_fixture_name) { "url_dependency.toml" }

      it { is_expected.to include("pytest = \"6.2.4\"\n") }
      it "does not include the version for url deps" do
        expect(freeze_top_level_dependencies_except).to_not include(
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n"\
          "version = \"0.10.2\"\n"
        )
        expect(freeze_top_level_dependencies_except).to include(
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n"
        )
      end
    end
  end
end
