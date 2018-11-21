# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pipfile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PipfileFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("python", "pipfiles", pipfile_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("python", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "version_not_specified" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.18.4",
      previous_version: "2.18.0",
      package_manager: "pip",
      requirements: [{
        requirement: "*",
        file: "Pipfile",
        source: nil,
        groups: ["default"]
      }],
      previous_requirements: [{
        requirement: "*",
        file: "Pipfile",
        source: nil,
        groups: ["default"]
      }]
    )
  end
  let(:dependency_name) { "requests" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "with a capital letter" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      it "updates the lockfile successfully (and doesn't affect other deps)" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).
          to eq("==3.4.0")
      end
    end

    context "when the Pipfile hasn't changed" do
      let(:pipfile_fixture_name) { "version_not_specified" }
      let(:lockfile_fixture_name) { "version_not_specified.lock" }

      it "only returns the lockfile" do
        expect(updated_files.map(&:name)).to eq(["Pipfile.lock"])
      end
    end

    context "when the Pipfile specified a Python version" do
      let(:pipfile_fixture_name) { "required_python" }
      let(:lockfile_fixture_name) { "required_python.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it "updates both files correctly" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(updated_pipfile.content).
          to include('python_full_version = "2.7.15"')
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
        expect(json_lockfile["_meta"]["requires"]).
          to eq(JSON.parse(lockfile.content)["_meta"]["requires"])
        expect(json_lockfile["develop"]["funcsigs"]["markers"]).
          to eq("python_version < '3.0'")
      end

      context "and includes a .python-version file" do
        let(:dependency_files) { [pipfile, lockfile, python_version_file] }
        let(:python_version_file) do
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: "2.7.15\n"
          )
        end

        it "updates both files correctly" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))
        end
      end

      context "when the Python requirement is implicit" do
        let(:pipfile_fixture_name) { "required_python_implicit" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "pytest",
            version: "3.8.1",
            previous_version: "3.4.1",
            package_manager: "pip",
            requirements: [{
              requirement: "==3.8.1",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }],
            previous_requirements: [{
              requirement: "==3.4.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          )
        end

        it "updates both files correctly" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))
        end

        context "due to a version in the lockfile" do
          let(:pipfile_fixture_name) { "required_python_implicit_2" }
          let(:lockfile_fixture_name) { "required_python_implicit_2.lock" }

          it "updates both files correctly" do
            expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

            updated_lockfile = updated_files.find do |f|
              f.name == "Pipfile.lock"
            end
            json_lockfile = JSON.parse(updated_lockfile.content)

            expect(json_lockfile["develop"]["pytest"]["version"]).
              to eq("==3.8.1")
            expect(json_lockfile["default"]["futures"]["version"]).
              to eq("==3.2.0")
          end
        end
      end
    end

    context "when the Pipfile included an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          {
            "type" => "python_index",
            "index-url" => "https://pypi.python.org/simple"
          }
        ]
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it "updates both files correctly" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
        json_lockfile = JSON.parse(updated_lockfile.content)

        expect(updated_pipfile.content).
          to include("pypi.python.org/${ENV_VAR}")
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["_meta"]["sources"]).
          to eq([{ "url" => "https://pypi.python.org/${ENV_VAR}",
                   "verify_ssl" => true }])
        expect(updated_lockfile.content).
          to_not include("pypi.python.org/simple")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
      end
    end

    describe "the updated Pipfile.lock" do
      let(:updated_lockfile) do
        updated_files.find { |f| f.name == "Pipfile.lock" }
      end

      let(:json_lockfile) { JSON.parse(updated_lockfile.content) }

      it "updates only what it needs to" do
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        expect(json_lockfile["_meta"]["hash"]).
          to eq(JSON.parse(lockfile.content)["_meta"]["hash"])
      end

      describe "with a subdependency from an extra" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "raven",
            version: "6.7.0",
            previous_version: "5.27.1",
            package_manager: "pip",
            requirements: [{
              requirement: "==6.7.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }],
            previous_requirements: [{
              requirement: "==5.27.1",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          )
        end
        let(:pipfile_fixture_name) { "extra_subdependency" }
        let(:lockfile_fixture_name) { "extra_subdependency.lock" }

        it "doesn't remove the subdependency" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          expect(json_lockfile["default"]["raven"]["version"]).
            to eq("==6.7.0")
          expect(json_lockfile["default"]["blinker"]["version"]).
            to eq("==1.4")
        end
      end

      context "with a path dependency" do
        let(:dependency_files) { [pipfile, lockfile, setupfile] }
        let(:setupfile) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", setupfile_fixture_name)
          )
        end
        let(:setupfile_fixture_name) { "small.py" }
        let(:pipfile_fixture_name) { "path_dependency" }
        let(:lockfile_fixture_name) { "path_dependency.lock" }

        it "updates the dependency" do
          expect(json_lockfile["default"]["requests"]["version"]).
            to eq("==2.18.4")
        end

        context "that needs to be sanitized" do
          let(:setupfile_fixture_name) { "small_needs_sanitizing.py" }
          it "updates the dependency" do
            expect(json_lockfile["default"]["requests"]["version"]).
              to eq("==2.18.4")
          end
        end

        context "that imports a setup.cfg" do
          let(:dependency_files) do
            [pipfile, lockfile, setupfile, setup_cfg, requirements_file]
          end
          let(:setupfile_fixture_name) { "with_pbr.py" }
          let(:setup_cfg) do
            Dependabot::DependencyFile.new(
              name: "setup.cfg",
              content: fixture("python", "setup_files", "setup.cfg")
            )
          end
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("python", "requirements", "pbr.txt")
            )
          end

          it "updates the dependency" do
            expect(json_lockfile["default"]["requests"]["version"]).
              to eq("==2.18.4")
            expect(json_lockfile["default"]["pbr"]).to_not be_nil
          end
        end
      end
    end

    context "with a requirements.txt" do
      let(:dependency_files) { [pipfile, lockfile, requirements_file] }

      context "that looks like the output of `pipenv lock -r`" do
        let(:pipfile_fixture_name) { "hard_names" }
        let(:lockfile_fixture_name) { "hard_names.lock" }
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: fixture(
              "python",
              "requirements",
              "hard_names_runtime.txt"
            )
          )
        end

        it "updates the lockfile and the requirements.txt" do
          expect(updated_files.map(&:name)).
            to match_array(%w(Pipfile.lock requirements.txt))

          updated_lock = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_txt = updated_files.find { |f| f.name == "requirements.txt" }

          JSON.parse(updated_lock.content).fetch("default").each do |nm, hash|
            expect(updated_txt.content).to include("#{nm}#{hash['version']}")
          end
        end
      end

      context "that looks like the output of `pipenv lock -r -d`" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "req-dev.txt",
            content: fixture(
              "python",
              "requirements",
              "version_not_specified_dev.txt"
            )
          )
        end

        it "updates the lockfile and the requirements.txt" do
          expect(updated_files.map(&:name)).
            to match_array(%w(Pipfile.lock req-dev.txt))

          updated_lock = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_txt = updated_files.find { |f| f.name == "req-dev.txt" }

          JSON.parse(updated_lock.content).fetch("develop").each do |nm, hash|
            expect(updated_txt.content).to include("#{nm}#{hash['version']}")
          end
        end
      end

      context "that is unrelated" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: fixture("python", "requirements", "pbr.txt")
          )
        end

        it "updates the lockfile only" do
          expect(updated_files.map(&:name)).to match_array(%w(Pipfile.lock))
        end
      end
    end
  end

  describe "the updated pipfile" do
    # Only update a Pipfile (speeds up tests)
    let(:dependency_files) { [pipfile] }
    subject(:updated_pipfile_content) do
      updater.updated_dependency_files.find { |f| f.name == "Pipfile" }.content
    end

    let(:pipfile_fixture_name) { "version_not_specified" }

    context "with single quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python-decouple",
          version: "3.2",
          previous_version: "3.1",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.2",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==3.1",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it { is_expected.to include(%q('python_decouple' = "==3.2")) }
    end

    context "with double quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it { is_expected.to include('"requests" = "==2.18.4"') }
    end

    context "without quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pytest",
          version: "3.3.1",
          previous_version: "3.2.3",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.3.1",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }],
          previous_requirements: [{
            requirement: "==3.2.3",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }]
        )
      end

      it { is_expected.to include(%(\npytest = "==3.3.1"\n)) }
      it { is_expected.to include(%(\npytest-extension = "==3.2.3"\n)) }
      it { is_expected.to include(%(\nextension-pytest = "==3.2.3"\n)) }
    end

    context "with a capital letter" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [{
            requirement: "==2.18.4",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==2.18.0",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end
      let(:pipfile_fixture_name) { "hard_names" }

      it { is_expected.to include('Requests = "==2.18.4"') }
    end
  end
end
