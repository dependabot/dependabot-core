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
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
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
      let(:python_version) { "3.8.17" }
      let(:pyproject_fixture_name) { "python_38.toml" }
      let(:lockfile_fixture_name) { "python_38.lock" }
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
        [Dependabot::Credential.new({
          "type" => "python_index",
          "index-url" => "https://some.internal.registry.com/pypi/",
          "username" => "test",
          "password" => "test"
        })]
      end

      it "prepares a pyproject file without credentials in" do
        repo_obj = TomlRB.parse(prepared_project, symbolize_keys: true)[:tool][:poetry][:source]
        expect(repo_obj[0][:url]).to eq(credentials[0]["index-url"])

        user_pass = "#{credentials[0]['user']}:#{credentials[0]['password']}@"
        expect(repo_obj[0][:url]).not_to include(user_pass)
      end
    end
  end
end
