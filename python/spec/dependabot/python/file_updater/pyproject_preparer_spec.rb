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
  let(:pyproject_fixture_name) { "basic_poetry_dependencies.toml" }

  describe "#add_auth_env_vars" do
    it "adds auth env vars when a token is present" do
      preparer = Dependabot::Python::FileUpdater::PyprojectPreparer.new(
        pyproject_content: fixture("pyproject_files", "private_source.toml"),
        lockfile: nil
      )
      preparer.add_auth_env_vars([
        {
          "index-url" => "https://some.internal.registry.com/pypi/",
          "token" => "hello:world"
        }
      ])
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_USERNAME")).to eq("hello")
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_PASSWORD")).to eq("world")
    end

    it "has no effect when a token is not present" do
      preparer = Dependabot::Python::FileUpdater::PyprojectPreparer.new(
        pyproject_content: fixture("pyproject_files", "private_source.toml"),
        lockfile: nil
      )
      preparer.add_auth_env_vars([
        {
          "index-url" => "https://some.internal.registry.com/pypi/"
        }
      ])
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_USERNAME")).to eq(nil)
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_PASSWORD")).to eq(nil)
    end

    it "doesn't break when there are no private sources" do
      preparer = Dependabot::Python::FileUpdater::PyprojectPreparer.new(
        pyproject_content: pyproject_content,
        lockfile: nil
      )
      expect { preparer.add_auth_env_vars(nil) }.not_to raise_error
    end

    it "doesn't break when there are private sources but no credentials" do
      preparer = Dependabot::Python::FileUpdater::PyprojectPreparer.new(
        pyproject_content: fixture("pyproject_files", "private_source.toml"),
        lockfile: nil
      )
      expect { preparer.add_auth_env_vars(nil) }.not_to raise_error
    end
  end

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
    let(:pyproject_lock_fixture_name) { "poetry.lock" }

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
            "[tool.poetry.dependencies.celery]\n" \
            "extras = [\"redis\"]\n" \
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

    context "with a multiple constraint dependency" do
      let(:dependencies) { [] }

      let(:pyproject_lock_fixture_name) { "multiple_constraint_dependency.lock" }
      let(:pyproject_fixture_name) { "multiple_constraint_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }

      it "does not touch multiple constraint deps" do
        expect(freeze_top_level_dependencies_except).not_to include("numpy = \"1.21.6\"")
      end
    end

    context "with directory dependency" do
      let(:dependencies) { [] }

      let(:pyproject_lock_fixture_name) { "dir_dependency.lock" }
      let(:pyproject_fixture_name) { "dir_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }
      it "does not include the version for path deps" do
        expect(freeze_top_level_dependencies_except).to_not include(
          "path = \"../toml\"\n" \
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
          "path = \"toml-8.2.54.tar.gz\"\n" \
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
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n" \
          "version = \"0.10.2\"\n"
        )
        expect(freeze_top_level_dependencies_except).to include(
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n"
        )
      end
    end
  end
end
