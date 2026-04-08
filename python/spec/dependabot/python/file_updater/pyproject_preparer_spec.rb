# typed: false
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
      preparer = described_class.new(
        pyproject_content: fixture("pyproject_files", "private_source.toml"),
        lockfile: nil
      )
      preparer.add_auth_env_vars(
        [
          {
            "index-url" => "https://some.internal.registry.com/pypi/",
            "token" => "hello:world"
          }
        ]
      )
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_USERNAME")).to eq("hello")
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_PASSWORD")).to eq("world")
    end

    it "has no effect when a token is not present" do
      preparer = described_class.new(
        pyproject_content: fixture("pyproject_files", "private_source.toml"),
        lockfile: nil
      )
      preparer.add_auth_env_vars(
        [
          {
            "index-url" => "https://some.internal.registry.com/pypi/"
          }
        ]
      )
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_USERNAME")).to be_nil
      expect(ENV.delete("POETRY_HTTP_BASIC_CUSTOM_SOURCE_1_PASSWORD")).to be_nil
    end

    it "doesn't break when there are no private sources" do
      preparer = described_class.new(
        pyproject_content: pyproject_content,
        lockfile: nil
      )
      expect { preparer.add_auth_env_vars(nil) }.not_to raise_error
    end

    it "doesn't break when there are private sources but no credentials" do
      preparer = described_class.new(
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
        name: "poetry.lock",
        content: poetry_lock_body
      )
    end
    let(:poetry_lock_body) do
      fixture("poetry_locks", poetry_lock_fixture_name)
    end
    let(:poetry_lock_fixture_name) { "poetry.lock" }

    context "with no dependencies to except" do
      let(:dependencies) { [] }

      it { is_expected.to include("geopy = \"1.14.0\"\n") }
      it { is_expected.to include("hypothesis = \"3.57.0\"\n") }
      it { is_expected.to include("python = \"^3.6 || ^3.7\"\n") }

      context "with extras" do
        let(:pyproject_fixture_name) { "extras.toml" }
        let(:poetry_lock_fixture_name) { "extras.lock" }

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

      let(:poetry_lock_fixture_name) { "multiple_constraint_dependency.lock" }
      let(:pyproject_fixture_name) { "multiple_constraint_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }

      it "does not touch multiple constraint deps" do
        expect(freeze_top_level_dependencies_except).not_to include("numpy = \"1.21.6\"")
      end
    end

    context "with directory dependency" do
      let(:dependencies) { [] }

      let(:poetry_lock_fixture_name) { "dir_dependency.lock" }
      let(:pyproject_fixture_name) { "dir_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }

      it "does not include the version for path deps" do
        expect(freeze_top_level_dependencies_except).not_to include(
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

      let(:poetry_lock_fixture_name) { "file_dependency.lock" }
      let(:pyproject_fixture_name) { "file_dependency.toml" }

      it { is_expected.to include("pytest = \"3.7.4\"\n") }

      it "does not include the version for path deps" do
        expect(freeze_top_level_dependencies_except).not_to include(
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

      let(:poetry_lock_fixture_name) { "url_dependency.lock" }
      let(:pyproject_fixture_name) { "url_dependency.toml" }

      it { is_expected.to include("pytest = \"6.2.4\"\n") }

      it "does not include the version for url deps" do
        expect(freeze_top_level_dependencies_except).not_to include(
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n" \
          "version = \"0.10.2\"\n"
        )
        expect(freeze_top_level_dependencies_except).to include(
          "url = \"https://github.com/uiri/toml/archive/refs/tags/0.10.2.tar.gz\"\n"
        )
      end
    end

    context "with a git dependency in a subdirectory" do
      let(:dependencies) { [] }

      let(:poetry_lock_fixture_name) { "git_dependency_in_a_subdirectory.lock" }
      let(:pyproject_fixture_name) { "git_dependency_in_a_subdirectory.toml" }

      it { is_expected.to include("subdirectory = \"python\"\n") }
    end

    context "with PEP 621 project.dependencies" do
      let(:dependencies) { [] }
      let(:pyproject_fixture_name) { "pep621_hybrid_version_in_both.toml" }
      let(:poetry_lock_fixture_name) { "caret_version.lock" }

      it "freezes PEP 621 dependencies to their locked versions" do
        result = freeze_top_level_dependencies_except
        parsed = TomlRB.parse(result)
        project_deps = parsed.dig("project", "dependencies")
        requests_dep = project_deps.find { |d| d.start_with?("requests") }
        expect(requests_dep).to eq("requests==1.2.3")
      end

      it "also freezes tool.poetry.dependencies" do
        result = freeze_top_level_dependencies_except
        parsed = TomlRB.parse(result)
        poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
        expect(poetry_req["version"]).to eq("1.2.3")
      end

      context "when excluding a dependency" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "requests",
              version: "2.19.1",
              package_manager: "pip",
              requirements: []
            )
          ]
        end

        it "does not freeze the excluded PEP 621 dependency" do
          result = freeze_top_level_dependencies_except
          parsed = TomlRB.parse(result)
          project_deps = parsed.dig("project", "dependencies")
          requests_dep = project_deps.find { |d| d.start_with?("requests") }
          expect(requests_dep).to eq("requests>=2.13.0")
        end
      end
    end

    context "with PEP 621 dependencies containing environment markers" do
      let(:dependencies) { [] }
      let(:pyproject_fixture_name) { "pep621_hybrid_with_markers.toml" }
      let(:poetry_lock_fixture_name) { "caret_version.lock" }

      it "freezes the version while preserving markers" do
        result = freeze_top_level_dependencies_except
        parsed = TomlRB.parse(result)
        project_deps = parsed.dig("project", "dependencies")
        requests_dep = project_deps.find { |d| d.start_with?("requests") }
        expect(requests_dep).to eq("requests==1.2.3 ; python_version >= '3.7'")
      end
    end

    context "with PEP 621 project.optional-dependencies" do
      let(:dependencies) { [] }
      let(:pyproject_fixture_name) { "pep621_hybrid_optional_deps.toml" }
      let(:poetry_lock_fixture_name) { "caret_version.lock" }

      it "freezes optional dependencies to their locked versions" do
        result = freeze_top_level_dependencies_except
        parsed = TomlRB.parse(result)
        opt_deps = parsed.dig("project", "optional-dependencies", "networking")
        requests_dep = opt_deps.find { |d| d.start_with?("requests") }
        expect(requests_dep).to eq("requests==1.2.3")
      end
    end
  end
end
