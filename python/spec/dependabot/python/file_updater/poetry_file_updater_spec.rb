# typed: false
# frozen_string_literal: true

require "toml-rb"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/poetry_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::PoetryFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "poetry.lock",
      content: fixture("poetry_locks", lockfile_fixture_name)
    )
  end
  let(:pyproject_fixture_name) { "version_not_specified.toml" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.19.1",
      previous_version: "2.18.0",
      package_manager: "pip",
      requirements: [{
        requirement: "*",
        file: "pyproject.toml",
        source: nil,
        groups: ["dependencies"]
      }],
      previous_requirements: [{
        requirement: "*",
        file: "pyproject.toml",
        source: nil,
        groups: ["dependencies"]
      }]
    )
  end
  let(:dependency_name) { "requests" }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the lockfile successfully (and doesn't affect other deps)" do
      expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

      updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

      lockfile_obj = TomlRB.parse(updated_lockfile.content)
      requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
      pytest = lockfile_obj["package"].find { |d| d["name"] == "pytest" }

      expect(requests["version"]).to eq("2.19.1")
      expect(pytest["version"]).to eq("3.5.0")

      expect(lockfile_obj["metadata"]["content-hash"])
        .to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040")
    end

    context "with a specified Python version" do
      let(:pyproject_fixture_name) { "python_310.toml" }
      let(:lockfile_fixture_name) { "python_310.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.19.1",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "2.19.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "2.18.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "updates the lockfile successfully" do
        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
        expect(requests["version"]).to eq("2.19.1")
      end

      it "does not change python version" do
        updated_pyproj = updated_files.find { |f| f.name == "pyproject.toml" }
        pyproj_obj = TomlRB.parse(updated_pyproj.content)
        expect(pyproj_obj["tool"]["poetry"]["dependencies"]["python"]).to eq("3.10.7")

        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }
        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        expect(lockfile_obj["metadata"]["python-versions"]).to eq("3.10.7")
      end
    end

    context "with the oldest python version currently supported by Dependabot" do
      let(:python_version) { "3.9.21" }
      let(:pyproject_fixture_name) { "python_39.toml" }
      let(:lockfile_fixture_name) { "python_39.lock" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "django",
          version: "3.1",
          previous_version: "3.0",
          package_manager: "pip",
          requirements: [{
            requirement: "*",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "*",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "updates the lockfile" do
        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "django" }
        expect(requests["version"]).to eq("3.1")
      end
    end

    context "with a pyproject.toml file" do
      let(:dependency_files) { [pyproject] }

      context "without a lockfile" do
        let(:pyproject_fixture_name) { "caret_version.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2.19.1",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "^1.0.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }
          expect(updated_lockfile.content).to include('requests = "^2.19.1"')
        end
      end

      context "with CRLF line endings" do
        let(:pyproject_fixture_name) { "caret_version_crlf.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2.19.1",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "^1.0.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }
          expect(updated_lockfile.content).to include('requests = "^2.19.1"')
        end
      end

      context "when dealing with indented" do
        let(:pyproject_fixture_name) { "indented.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2.19.1",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "^1.0.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }
          expect(updated_lockfile.content).to include('  requests = "^2.19.1"')
        end
      end

      context "when specifying table style dependencies" do
        let(:pyproject_fixture_name) { "table.toml" }
        let(:dependency_name) { "isort" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "5.7.0",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^5.7",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }],
            previous_requirements: [{
              requirement: "^5.4",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dev-dependencies.isort]
            version = "^5.7"
          TOML
        end
      end

      context "when specifying table style dependencies with version as the last field" do
        let(:pyproject_fixture_name) { "table_version_last.toml" }
        let(:dependency_name) { "isort" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "5.7.0",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^5.7",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }],
            previous_requirements: [{
              requirement: "^5.4",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dev-dependencies.isort]
            extras = [ "pyproject",]
            version = "^5.7"
          TOML
        end
      end

      context "when specifying table style dependencies with version conflicting with other deps" do
        let(:pyproject_fixture_name) { "table_version_conflicts.toml" }
        let(:dependency_name) { "isort" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "5.7.0",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^5.7",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }],
            previous_requirements: [{
              requirement: "^5.4",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dev-dependencies.isort]
            extras = [ "pyproject",]
            version = "^5.7"

            [tool.poetry.dev-dependencies.pytest]
            extras = [ "pyproject",]
            version = "^5.4"
          TOML
        end
      end

      context "with same dep specified twice in different groups (legacy syntax)" do
        let(:pyproject_fixture_name) { "different_requirements_legacy.toml" }
        let(:dependency_name) { "streamlit" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.27.2",
            previous_version: "1.18.1",
            package_manager: "pip",
            requirements: [{
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: "^1.27.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }],
            previous_requirements: [{
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: "^1.12.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dependencies]
            streamlit = ">=0.65.0"
            packaging = ">=20.0"

            [tool.poetry.dev-dependencies]
            black = "^20.8b1"
            isort = "^5.12.0"
            flake8 = "^4.0.1"
            mypy = "^1.6"
            pytest = "^7.4.2"
            streamlit = "^1.27.2"
          TOML
        end
      end

      context "with same dep specified twice in different groups (updated is in main)" do
        let(:pyproject_fixture_name) { "different_requirements_main.toml" }
        let(:dependency_name) { "streamlit" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.27.2",
            previous_version: "1.18.1",
            package_manager: "pip",
            requirements: [{
              requirement: "^1.27.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }],
            previous_requirements: [{
              requirement: "^1.12.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev-dependencies"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dependencies]
            packaging = ">=20.0"
            streamlit = "^1.27.2"

            [tool.poetry.dev-dependencies]
            black = "^20.8b1"
            isort = "^5.12.0"
            flake8 = "^4.0.1"
            mypy = "^1.6"
            pytest = "^7.4.2"
            streamlit = ">=0.65.0"
          TOML
        end
      end

      context "with same dep specified twice in different groups" do
        let(:pyproject_fixture_name) { "different_requirements.toml" }
        let(:dependency_name) { "streamlit" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.27.2",
            previous_version: "1.18.1",
            package_manager: "pip",
            requirements: [{
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: "^1.27.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev"]
            }],
            previous_requirements: [{
              requirement: ">=0.65.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }, {
              requirement: "^1.12.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev"]
            }]
          )
        end

        it "updates the pyproject.toml correctly" do
          expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

          updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

          expect(updated_lockfile.content).to include <<~TOML
            [tool.poetry.dependencies]
            streamlit = ">=0.65.0"
            packaging = ">=20.0"

            [tool.poetry.group.dev.dependencies]
            black = "^20.8b1"
            isort = "^5.12.0"
            flake8 = "^4.0.1"
            mypy = "^1.6"
            pytest = "^7.4.2"
            streamlit = "^1.27.2"
          TOML
        end
      end

      context "with inline comments in the dependencies groups" do
        let(:pyproject_fixture_name) { "inline_comments.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.27.2",
            previous_version: "1.18.1",
            package_manager: "pip",
            requirements: requirements,
            previous_requirements: previous_requirements
          )
        end

        context "when dealing with the dependency in the main dependencies group" do
          let(:dependency_name) { "jsonschema" }
          let(:requirements) do
            [{
              requirement: "^4.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: "^4.18.5",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          end

          it "updates the pyproject.toml correctly" do
            expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

            updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

            expect(updated_lockfile.content).to include <<~TOML
              [tool.poetry.dependencies]  # Main (runtime) dependencies
              python = "~3.10"
              jsonschema = "^4.19.1"  # jsonschema library
              packaging = ">=20.0"

              [tool.poetry.group.dev.dependencies]        # Development (local) dependencies
              black = "^20.8b1"
              flake8 = "^4.0.1"                   # flake8
              flake8-implicit-str-concat = "^0.4.0"
              isort = "^5.9.3"
              mypy = "^1.6"

              [tool.poetry.group.test.dependencies]# Test dependencies
              coverage = {extras = ["toml"], version = "^7.3.2"}
              pytest = "^7.4.0"#pytest
              pytest-mock = ">=3.8.2"
            TOML
          end
        end

        context "when dealing with the dependency in the dev dependencies group with multiple spaces" do
          let(:dependency_name) { "isort" }
          let(:requirements) do
            [{
              requirement: "^5.12.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev"]
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: "^5.9.3",
              file: "pyproject.toml",
              source: nil,
              groups: ["dev"]
            }]
          end

          it "updates the pyproject.toml correctly" do
            expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

            updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

            expect(updated_lockfile.content).to include <<~TOML
              [tool.poetry.dependencies]  # Main (runtime) dependencies
              python = "~3.10"
              jsonschema = "^4.18.5"  # jsonschema library
              packaging = ">=20.0"

              [tool.poetry.group.dev.dependencies]        # Development (local) dependencies
              black = "^20.8b1"
              flake8 = "^4.0.1"                   # flake8
              flake8-implicit-str-concat = "^0.4.0"
              isort = "^5.12.0"
              mypy = "^1.6"

              [tool.poetry.group.test.dependencies]# Test dependencies
              coverage = {extras = ["toml"], version = "^7.3.2"}
              pytest = "^7.4.0"#pytest
              pytest-mock = ">=3.8.2"
            TOML
          end
        end

        context "when dealing with the dependency in the test dependencies group without spaces" do
          let(:dependency_name) { "pytest-mock" }
          let(:requirements) do
            [{
              requirement: ">=3.12.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["test"]
            }]
          end
          let(:previous_requirements) do
            [{
              requirement: ">=3.8.2",
              file: "pyproject.toml",
              source: nil,
              groups: ["test"]
            }]
          end

          it "updates the pyproject.toml correctly" do
            expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

            updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

            expect(updated_lockfile.content).to include <<~TOML
              [tool.poetry.dependencies]  # Main (runtime) dependencies
              python = "~3.10"
              jsonschema = "^4.18.5"  # jsonschema library
              packaging = ">=20.0"

              [tool.poetry.group.dev.dependencies]        # Development (local) dependencies
              black = "^20.8b1"
              flake8 = "^4.0.1"                   # flake8
              flake8-implicit-str-concat = "^0.4.0"
              isort = "^5.9.3"
              mypy = "^1.6"

              [tool.poetry.group.test.dependencies]# Test dependencies
              coverage = {extras = ["toml"], version = "^7.3.2"}
              pytest = "^7.4.0"#pytest
              pytest-mock = ">=3.12.0"
            TOML
          end
        end
      end

      context "with the same requirement specified in two dependencies" do
        let(:pyproject_fixture_name) { "same_requirements.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.15.0",
            previous_version: "1.13.0",
            package_manager: "pip",
            requirements: [{
              requirement: "^1.15.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "^1.13.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        end

        context "when dealing with the first dependency" do
          let(:dependency_name) { "rq" }

          it "updates the pyproject.toml correctly" do
            expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

            updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

            expect(updated_lockfile.content).to include <<~TOML
              [tool.poetry]
              name = "dependabot-poetry-bug"
              version = "0.1.0"
              description = ""
              authors = []

              [tool.poetry.dependencies]
              python = "^3.9"
              rq = "^1.15.0"
              dramatiq = "^1.13.0"

              [build-system]
              requires = ["poetry-core"]
              build-backend = "poetry.core.masonry.api"
            TOML
          end
        end

        context "when dealing with the second dependency" do
          let(:dependency_name) { "dramatiq" }

          it "updates the pyproject.toml correctly" do
            expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))

            updated_lockfile = updated_files.find { |f| f.name == "pyproject.toml" }

            expect(updated_lockfile.content).to include <<~TOML
              [tool.poetry]
              name = "dependabot-poetry-bug"
              version = "0.1.0"
              description = ""
              authors = []

              [tool.poetry.dependencies]
              python = "^3.9"
              rq = "^1.13.0"
              dramatiq = "^1.15.0"

              [build-system]
              requires = ["poetry-core"]
              build-backend = "poetry.core.masonry.api"
            TOML
          end
        end
      end

      context "when the requirement has not changed" do
        let(:pyproject_fixture_name) { "caret_version.toml" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2.19.1",
            previous_version: nil,
            package_manager: "pip",
            requirements: [{
              requirement: "^2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: ">=2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        end

        it "raises the correct error" do
          expect do
            updated_files.map(&:name)
          end.to raise_error(Dependabot::DependencyFileContentNotChanged, "Content did not change!")
        end
      end
    end

    context "with a poetry.lock" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("poetry_locks", lockfile_fixture_name)
        )
      end

      it "updates the lockfile successfully" do
        expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
        pytest = lockfile_obj["package"].find { |d| d["name"] == "pytest" }

        expect(requests["version"]).to eq("2.19.1")
        expect(pytest["version"]).to eq("3.5.0")

        expect(lockfile_obj["metadata"]["content-hash"])
          .to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040a1d")
      end

      context "with a sub-dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "2018.11.29",
            previous_version: "2018.4.16",
            package_manager: "pip",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependency_name) { "certifi" }

        it "updates the lockfile successfully" do
          expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

          updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

          lockfile_obj = TomlRB.parse(updated_lockfile.content)
          certifi = lockfile_obj["package"].find { |d| d["name"] == "certifi" }

          expect(certifi["version"]).to eq("2018.11.29")

          expect(lockfile_obj["metadata"]["content-hash"])
            .to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040a")
        end
      end
    end

    context "with a non-package mode project" do
      let(:pyproject_fixture_name) { "poetry_non_package_mode_simple.toml" }
      let(:lockfile_fixture_name) { "version_not_specified.lock" }

      it "updates the lockfile successfully" do
        expect(updated_files.map(&:name)).to eq(%w(poetry.lock))

        updated_lockfile = updated_files.find { |f| f.name == "poetry.lock" }

        lockfile_obj = TomlRB.parse(updated_lockfile.content)
        requests = lockfile_obj["package"].find { |d| d["name"] == "requests" }
        pytest = lockfile_obj["package"].find { |d| d["name"] == "pytest" }

        expect(requests["version"]).to eq("2.19.1")
        expect(pytest["version"]).to eq("3.5.0")

        expect(lockfile_obj["metadata"]["content-hash"])
          .to start_with("8cea4ecb5b2230fbd4a33a67a4da004f1ccabad48352aaf040")
      end
    end
  end

  describe "constraint-only update with unchanged lockfile" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:dependency_files) { [pyproject, lockfile] }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "poetry.lock",
        content: fixture("poetry_locks", lockfile_fixture_name)
      )
    end
    let(:pyproject_fixture_name) { "caret_version.toml" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "2.18.0",
        previous_version: "1.0.0",
        package_manager: "pip",
        requirements: [{
          requirement: "^2.18.0",
          file: "pyproject.toml",
          source: nil,
          groups: ["dependencies"]
        }],
        previous_requirements: [{
          requirement: "^1.0.0",
          file: "pyproject.toml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    it "returns only the updated pyproject without raising" do
      # Stub lockfile generation to return the original lockfile content
      # simulating the case where bumping a lower bound doesn't affect resolution
      allow(updater).to receive(:updated_lockfile_content).and_return(lockfile.content)

      expect(updated_files.map(&:name)).to eq(%w(pyproject.toml))
    end
  end

  describe "hybrid Poetry v2 projects" do
    let(:dependency_files) { [pyproject] }

    context "when dependency has version in both project.dependencies and tool.poetry.dependencies" do
      let(:pyproject_fixture_name) { "pep621_hybrid_version_in_both.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.19.1",
          previous_version: "2.13.0",
          package_manager: "pip",
          requirements: [
            {
              requirement: ">=2.19.1",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            },
            {
              requirement: "^2.19",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }
          ],
          previous_requirements: [
            {
              requirement: ">=2.13.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            },
            {
              requirement: "^2.13",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }
          ],
          metadata: { source_requirement: ">=2.13.0" }
        )
      end

      describe "#updated_dependency_files" do
        subject(:updated_files) { updater.updated_dependency_files }

        it "updates the version in project.dependencies" do
          updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
          expect(updated_pyproject.content).to include('"requests>=2.19.1"')
          expect(updated_pyproject.content).not_to include('"requests>=2.13.0"')
        end

        it "updates the version in tool.poetry.dependencies" do
          updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
          parsed = TomlRB.parse(updated_pyproject.content)
          poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
          expect(poetry_req["version"]).to eq("^2.19")
        end

        it "preserves enrichment metadata in tool.poetry.dependencies" do
          updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
          parsed = TomlRB.parse(updated_pyproject.content)
          poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
          expect(poetry_req["source"]).to eq("private-source")
        end
      end
    end

    context "when tool.poetry.dependencies has enrichment only (no version key)" do
      let(:pyproject_fixture_name) { "pep621_hybrid_enrichment_only.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.19.1",
          previous_version: "2.13.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.19.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.13.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.13.0" }
        )
      end

      describe "#updated_dependency_files" do
        subject(:updated_files) { updater.updated_dependency_files }

        it "updates the version in project.dependencies" do
          updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
          expect(updated_pyproject.content).to include('"requests>=2.19.1"')
          expect(updated_pyproject.content).not_to include('"requests>=2.13.0"')
        end

        it "leaves the enrichment-only entry in tool.poetry.dependencies unchanged" do
          updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
          parsed = TomlRB.parse(updated_pyproject.content)
          poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
          expect(poetry_req).to eq({ "source" => "private-source" })
        end
      end
    end
  end

  describe "Poetry v2 fixtures (manifest updates)" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:dependency_files) { [pyproject] }

    context "with a PEP 621 only project" do
      let(:pyproject_fixture_name) { "poetry_v2_pep621_only.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0,<3.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0,<3.0"')
        expect(updated_pyproject.content).not_to include('"requests>=2.28.0,<3.0"')
      end

      it "preserves the poetry-core>=2.0 build backend" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("build-system", "requires")).to eq(["poetry-core>=2.0.0,<3.0.0"])
      end

      it "preserves the untouched urllib3 dependency" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"urllib3>=1.26.0"')
      end
    end

    context "with a hybrid PEP 621 + tool.poetry enrichment project" do
      let(:pyproject_fixture_name) { "poetry_v2_hybrid.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [
            {
              requirement: ">=2.31.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            },
            {
              requirement: "^2.31",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }
          ],
          previous_requirements: [
            {
              requirement: ">=2.28.0",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            },
            {
              requirement: "^2.28",
              file: "pyproject.toml",
              source: nil,
              groups: ["dependencies"]
            }
          ],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
        expect(updated_pyproject.content).not_to include('"requests>=2.28.0"')
      end

      it "updates the version in tool.poetry.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
        expect(poetry_req["version"]).to eq("^2.31")
      end

      it "preserves the private-source enrichment on the dependency" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        poetry_req = parsed.dig("tool", "poetry", "dependencies", "requests")
        expect(poetry_req["source"]).to eq("private-source")
      end

      it "preserves the [[tool.poetry.source]] block" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        sources = parsed.dig("tool", "poetry", "source")
        expect(sources.first["name"]).to eq("private-source")
        expect(sources.first["url"]).to eq("https://private.example.com/simple")
      end
    end

    context "with dynamic dependencies managed by Poetry" do
      let(:pyproject_fixture_name) { "poetry_v2_dynamic.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "django",
          version: "5.1.0",
          previous_version: "5.0.0",
          package_manager: "pip",
          requirements: [{
            requirement: "^5.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "^5.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: "^5.0.0" }
        )
      end

      it "updates the version in tool.poetry.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("tool", "poetry", "dependencies", "django")).to eq("^5.1")
      end

      it "preserves the dynamic marker in project metadata" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("project", "dynamic")).to eq(["dependencies"])
      end
    end

    context "with a requires-poetry constraint" do
      let(:pyproject_fixture_name) { "poetry_v2_requires_poetry.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
      end

      it "preserves the requires-poetry constraint" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("tool", "poetry", "requires-poetry")).to eq(">=2.0")
      end
    end

    context "with requires-plugins declared" do
      let(:pyproject_fixture_name) { "poetry_v2_requires_plugins.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
      end

      it "preserves requires-plugins and its version constraints" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        plugins = parsed.dig("tool", "poetry", "requires-plugins")
        expect(plugins["poetry-plugin-export"]).to eq(">=1.8.0")
      end
    end

    context "with package-mode = false" do
      let(:pyproject_fixture_name) { "poetry_v2_package_mode_false.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
      end

      it "preserves package-mode = false" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("tool", "poetry", "package-mode")).to be(false)
      end
    end

    context "with dependency groups and markers" do
      let(:pyproject_fixture_name) { "poetry_v2_groups_markers.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
      end

      it "preserves [dependency-groups] dev and docs groups" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        groups = parsed["dependency-groups"]
        expect(groups["dev"]).to include("pytest>=7.0", "black>=23.0")
        expect(groups["docs"]).to eq(["sphinx>=6.0"])
      end

      it "preserves the conditional colorama marker line" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include("colorama>=0.4.6")
        expect(updated_pyproject.content).to include("sys_platform == 'win32'")
      end
    end

    context "with project.optional-dependencies" do
      let(:pyproject_fixture_name) { "poetry_v2_optional_deps.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "cryptography",
          version: "42.0.0",
          previous_version: "41.0.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=42.0.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["security"]
          }],
          previous_requirements: [{
            requirement: ">=41.0.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["security"]
          }],
          metadata: { source_requirement: ">=41.0.0" }
        )
      end

      it "updates the version in the security optional group" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"cryptography>=42.0.0"')
        expect(updated_pyproject.content).not_to include('"cryptography>=41.0.0"')
      end

      it "leaves the unrelated socks extras untouched" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("project", "optional-dependencies", "socks"))
          .to eq(["PySocks>=1.5.6,!=1.5.7"])
      end

      it "leaves the main project.dependencies untouched" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.28.0"')
      end
    end

    context "with a legacy poetry-core>=1.0 build system" do
      let(:pyproject_fixture_name) { "poetry_v2_legacy_build_system.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.31.0",
          previous_version: "2.28.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.28.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.28.0" }
        )
      end

      it "updates the version in project.dependencies" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.31.0"')
      end

      it "preserves the legacy poetry-core>=1.0 build-system requires" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        parsed = TomlRB.parse(updated_pyproject.content)
        expect(parsed.dig("build-system", "requires")).to eq(["poetry-core>=1.0.0"])
      end
    end
  end

  describe "plugin installation during update" do
    it "invokes the poetry plugin installer" do
      plugin_installer = instance_double(
        Dependabot::Python::PoetryPluginInstaller,
        install_required_plugins: nil
      )
      allow(Dependabot::Python::PoetryPluginInstaller)
        .to receive(:from_dependency_files).and_return(plugin_installer)
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
      allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
      allow(updater).to receive_messages(
        write_temporary_dependency_files: nil,
        add_auth_env_vars: nil
      )

      language_version_manager = instance_double(
        Dependabot::Python::LanguageVersionManager,
        install_required_python: nil,
        python_version: "3.12.0"
      )
      allow(updater).to receive(:language_version_manager).and_return(language_version_manager)

      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("poetry.lock").and_return("lock content")

      begin
        updater.updated_dependency_files
      rescue StandardError
        nil
      end

      expect(plugin_installer).to have_received(:install_required_plugins)
    end
  end

  describe "#prepared_project_file" do
    subject(:prepared_project) { updater.send(:prepared_pyproject) }

    context "with a python_index with auth details" do
      let(:pyproject_fixture_name) { "private_secondary_source.toml" }
      let(:lockfile_fixture_name) { "private_secondary_source.lock" }
      let(:dependency_name) { "luigi" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.8.9",
          previous_version: "2.8.8",
          package_manager: "pip",
          requirements: [{
            requirement: "2.8.9",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "2.8.8",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end
      let(:credentials) do
        [Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://some.internal.registry.com/pypi/",
            "username" => "test",
            "password" => "test"
          }
        )]
      end

      it "prepares a pyproject file without credentials in" do
        repo_obj = TomlRB.parse(prepared_project, symbolize_keys: true)[:tool][:poetry][:source]
        expect(repo_obj[0][:url]).to eq(credentials[0]["index-url"])

        user_pass = "#{credentials[0]['user']}:#{credentials[0]['password']}@"
        expect(repo_obj[0][:url]).not_to include(user_pass)
      end
    end
  end

  describe "PEP 621 project.dependencies" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:dependency_files) { [pyproject] }

    context "with a simple exact version" do
      let(:pyproject_fixture_name) { "pep621_project_dependencies.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.14.0",
          previous_version: "2.13.0",
          package_manager: "pip",
          requirements: [{
            requirement: "<3.0,>=2.14.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "<3.0,>=2.13.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">=2.13.0,<3.0" }
        )
      end

      it "updates the version in pyproject.toml" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.14.0,<3.0"')
        expect(updated_pyproject.content).not_to include('"requests>=2.13.0,<3.0"')
      end

      it "preserves other dependencies unchanged" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"urllib3>=1.21.1"')
      end
    end

    context "with extras in the dependency" do
      let(:pyproject_fixture_name) { "pep621_poetry_with_extras.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "cachecontrol",
          version: "0.15.0",
          previous_version: "0.14.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=0.15.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=0.14.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: {
            extras: "filecache",
            source_requirement: ">=0.14.0"
          }
        )
      end

      it "updates the version while preserving extras" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"cachecontrol[filecache]>=0.15.0"')
        expect(updated_pyproject.content).not_to include('"cachecontrol[filecache]>=0.14.0"')
      end
    end
  end

  describe "PEP 621 project.optional-dependencies" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:dependency_files) { [pyproject] }
    let(:pyproject_fixture_name) { "pep621_optional_dependencies.toml" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "pysocks",
        version: "1.6.0",
        previous_version: "1.5.6",
        package_manager: "pip",
        requirements: [{
          requirement: "!=1.5.7,<2,>=1.6.0",
          file: "pyproject.toml",
          source: nil,
          groups: ["socks"]
        }],
        previous_requirements: [{
          requirement: "!=1.5.7,<2,>=1.5.6",
          file: "pyproject.toml",
          source: nil,
          groups: ["socks"]
        }],
        metadata: { source_requirement: ">= 1.5.6, != 1.5.7, < 2" }
      )
    end

    it "updates the optional dependency preserving formatting" do
      updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
      expect(updated_pyproject.content).to include("'PySocks >= 1.6.0, != 1.5.7, < 2'")
      expect(updated_pyproject.content).not_to include("'PySocks >= 1.5.6, != 1.5.7, < 2'")
    end

    it "preserves single quote style" do
      updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
      pysocks_line = updated_pyproject.content.lines.find { |l| l.include?("PySocks") }
      expect(pysocks_line).to include("'PySocks")
    end
  end

  describe "PEP 621 fallback without source_requirement metadata" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:dependency_files) { [pyproject] }

    context "when source_requirement is absent (e.g. after DependencySet merge)" do
      let(:pyproject_fixture_name) { "pep621_project_dependencies.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.14.0",
          previous_version: "2.13.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.14.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.13.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: {}
        )
      end

      it "updates using the normalized requirement as fallback" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests>=2.14.0,<3.0"')
        expect(updated_pyproject.content).not_to include('"requests>=2.13.0,<3.0"')
      end
    end
  end

  describe "PEP 508 version specifier formatting" do
    let(:pep621_updater) { described_class::Pep621Updater.new(dep: dependency) }

    describe "#rewrite_pep508_requirement" do
      subject(:result) { pep621_updater.rewrite_pep508_requirement(source_req, old_req, new_req) }

      context "with compact specifiers (no spaces)" do
        let(:source_req) { ">=2.13.0,<3.0" }
        let(:old_req) { ">=2.13.0,<3.0" }
        let(:new_req) { ">=2.14.0,<3.0" }

        it "rewrites the changed version" do
          expect(result).to eq(">=2.14.0,<3.0")
        end
      end

      context "with spaced specifiers" do
        let(:source_req) { ">= 2.13.0, < 3.0" }
        let(:old_req) { ">=2.13.0,<3.0" }
        let(:new_req) { ">=2.14.0,<3.0" }

        it "preserves whitespace around operators" do
          expect(result).to eq(">= 2.14.0, < 3.0")
        end
      end

      context "with multiple specifiers including != and <" do
        let(:source_req) { ">= 1.5.6, != 1.5.7, < 2" }
        let(:old_req) { "!=1.5.7,<2,>=1.5.6" }
        let(:new_req) { "!=1.5.7,<2,>=1.6.0" }

        it "updates only the changed version preserving formatting" do
          expect(result).to eq(">= 1.6.0, != 1.5.7, < 2")
        end
      end

      context "with a single == specifier" do
        let(:source_req) { "==2.18.0" }
        let(:old_req) { "==2.18.0" }
        let(:new_req) { "==2.19.0" }

        it "rewrites the exact version" do
          expect(result).to eq("==2.19.0")
        end
      end

      context "with ~= compatible release" do
        let(:source_req) { "~= 1.4.2" }
        let(:old_req) { "~=1.4.2" }
        let(:new_req) { "~=1.5.0" }

        it "preserves spacing with tilde-equals" do
          expect(result).to eq("~= 1.5.0")
        end
      end

      context "when no version changes" do
        let(:source_req) { ">= 1.0, < 2.0" }
        let(:old_req) { ">=1.0,<2.0" }
        let(:new_req) { ">=1.0,<2.0" }

        it "returns the source unchanged" do
          expect(result).to eq(">= 1.0, < 2.0")
        end
      end
    end

    describe "#parse_specifiers" do
      subject(:specifiers) { pep621_updater.parse_specifiers(req) }

      context "with a compact multi-specifier string" do
        let(:req) { ">=2.13.0,<3.0" }

        it "parses each operator and version" do
          expect(specifiers).to eq(
            [
              { operator: ">=", version: "2.13.0" },
              { operator: "<", version: "3.0" }
            ]
          )
        end
      end

      context "with a single == specifier" do
        let(:req) { "==1.2.3" }

        it "returns one entry" do
          expect(specifiers).to eq([{ operator: "==", version: "1.2.3" }])
        end
      end

      context "with != and ~= operators" do
        let(:req) { "!=1.5.7,~=1.4.2" }

        it "parses both operators" do
          expect(specifiers).to eq(
            [
              { operator: "!=", version: "1.5.7" },
              { operator: "~=", version: "1.4.2" }
            ]
          )
        end
      end

      context "with an empty string" do
        let(:req) { "" }

        it "returns an empty array" do
          expect(specifiers).to eq([])
        end
      end
    end

    context "with spaced range specifiers (integration)" do
      subject(:updated_files) { updater.updated_dependency_files }

      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "pep508_specifiers.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.14.0",
          previous_version: "2.13.0",
          package_manager: "pip",
          requirements: [{
            requirement: ">=2.14.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=2.13.0,<3.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">= 2.13.0, < 3.0" }
        )
      end

      it "updates the version preserving whitespace" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"requests >= 2.14.0, < 3.0"')
        expect(updated_pyproject.content).not_to include('"requests >= 2.13.0, < 3.0"')
      end

      it "leaves other dependencies unchanged" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"urllib3==1.26.0"')
        expect(updated_pyproject.content).to include('"certifi ~= 2023.7.22"')
        expect(updated_pyproject.content).to include('"idna >= 3.4, != 3.5"')
      end
    end

    context "with an exact == specifier (integration)" do
      subject(:updated_files) { updater.updated_dependency_files }

      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "pep508_specifiers.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "urllib3",
          version: "1.26.1",
          previous_version: "1.26.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==1.26.1",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "==1.26.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: "==1.26.0" }
        )
      end

      it "updates the pinned version" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"urllib3==1.26.1"')
        expect(updated_pyproject.content).not_to include('"urllib3==1.26.0"')
      end
    end

    context "with a ~= compatible-release specifier (integration)" do
      subject(:updated_files) { updater.updated_dependency_files }

      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "pep508_specifiers.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "certifi",
          version: "2024.2.2",
          previous_version: "2023.7.22",
          package_manager: "pip",
          requirements: [{
            requirement: "~=2024.2.2",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "~=2023.7.22",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: "~= 2023.7.22" }
        )
      end

      it "updates the version preserving spacing around ~=" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"certifi ~= 2024.2.2"')
        expect(updated_pyproject.content).not_to include('"certifi ~= 2023.7.22"')
      end
    end

    context "with a != exclusion specifier (integration)" do
      subject(:updated_files) { updater.updated_dependency_files }

      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "pep508_specifiers.toml" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "idna",
          version: "3.6",
          previous_version: "3.4",
          package_manager: "pip",
          requirements: [{
            requirement: ">=3.6,!=3.5",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=3.4,!=3.5",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }],
          metadata: { source_requirement: ">= 3.4, != 3.5" }
        )
      end

      it "updates the lower bound while preserving the exclusion" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('"idna >= 3.6, != 3.5"')
        expect(updated_pyproject.content).not_to include('"idna >= 3.4, != 3.5"')
      end
    end
  end

  describe "Git dependencies" do
    let(:pyproject_fixture_name) { "git_dependency_with_tag.toml" }
    let(:dependency_files) { [pyproject] }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "fastapi",
        version: nil,
        previous_version: nil,
        package_manager: "pip",
        requirements: [{
          requirement: nil,
          file: "pyproject.toml",
          source: {
            type: "git",
            url: "https://github.com/tiangolo/fastapi",
            ref: "0.128.0",
            branch: nil
          },
          groups: ["dependencies"]
        }],
        previous_requirements: [{
          requirement: nil,
          file: "pyproject.toml",
          source: {
            type: "git",
            url: "https://github.com/tiangolo/fastapi",
            ref: "0.110.0",
            branch: nil
          },
          groups: ["dependencies"]
        }]
      )
    end

    describe "#updated_dependency_files" do
      subject(:updated_files) { updater.updated_dependency_files }

      it "updates only the pyproject.toml file" do
        expect(updated_files.map(&:name)).to eq(["pyproject.toml"])
      end

      it "updates the git tag in the pyproject file" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('tag = "0.128.0"')
        expect(updated_pyproject.content).not_to include('tag = "0.110.0"')
      end

      it "preserves the git URL and extras" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        expect(updated_pyproject.content).to include('git = "https://github.com/tiangolo/fastapi"')
        expect(updated_pyproject.content).to include('extras = ["all"]')
      end

      it "does not add a version field to the git dependency" do
        updated_pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
        fastapi_line = updated_pyproject.content.lines.find { |l| l.include?("fastapi") }
        expect(fastapi_line).not_to include("version")
      end
    end
  end
end
