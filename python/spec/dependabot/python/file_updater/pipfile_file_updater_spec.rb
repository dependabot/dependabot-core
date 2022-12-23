# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pipfile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::PipfileFileUpdater do
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
      content: fixture("pipfiles", pipfile_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
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
          to include('python_full_version = "3.9.4"')
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
        expect(json_lockfile["_meta"]["requires"]).
          to eq(JSON.parse(lockfile.content)["_meta"]["requires"])
      end

      context "that comes from a Poetry file and includes || logic" do
        let(:pipfile_fixture_name) { "exact_version" }
        let(:dependency_files) { [pipfile, lockfile, pyproject] }
        let(:pyproject) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "basic_poetry_dependencies.toml")
          )
        end

        it "updates both files correctly" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))
        end
      end

      context "and includes a .python-version file" do
        let(:dependency_files) { [pipfile, lockfile, python_version_file] }
        let(:python_version_file) do
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: "3.9.4\n"
          )
        end

        it "updates both files correctly" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))
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
            "index-url" => "https://pypi.org/simple"
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
          to include("pypi.org/${ENV_VAR}")
        expect(json_lockfile["default"]["requests"]["version"]).
          to eq("==2.18.4")
        expect(json_lockfile["_meta"]["sources"]).
          to eq([{ "url" => "https://pypi.org/${ENV_VAR}",
                   "verify_ssl" => true }])
        expect(updated_lockfile.content).
          to_not include("pypi.org/simple")
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

      describe "when updating a subdependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "py",
            version: "1.7.0",
            previous_version: "1.5.3",
            package_manager: "pip",
            requirements: [],
            previous_requirements: []
          )
        end

        it "updates only what it needs to" do
          expect(json_lockfile["default"].key?("py")).to eq(false)
          expect(json_lockfile["develop"]["py"]["version"]).to eq("==1.7.0")
          expect(json_lockfile["_meta"]["hash"]).
            to eq(JSON.parse(lockfile.content)["_meta"]["hash"])
        end
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

          expect(json_lockfile["default"]["raven"]["version"]).to eq("==6.7.0")
          expect(json_lockfile["default"]["blinker"]["version"]).to eq("==1.5")
        end
      end

      context "with a git dependency" do
        let(:pipfile_fixture_name) { "git_source_no_ref" }
        let(:lockfile_fixture_name) { "git_source_no_ref.lock" }

        context "when updating the non-git dependency" do
          it "doesn't update the git dependency", :slow do
            expect(json_lockfile["default"]["requests"]["version"]).
              to eq("==2.18.4")
            expect(json_lockfile["default"]["pythonfinder"]).
              to eq(JSON.parse(lockfile.content)["default"]["pythonfinder"])
          end
        end
      end

      context "with a path dependency", :slow do
        let(:dependency_files) { [pipfile, lockfile, setupfile] }
        let(:setupfile) do
          Dependabot::DependencyFile.new(
            name: "mydep/setup.py",
            content: fixture("setup_files", setupfile_fixture_name)
          )
        end
        let(:setupfile_fixture_name) { "small.py" }
        let(:pipfile_fixture_name) { "path_dependency_not_self" }
        let(:lockfile_fixture_name) { "path_dependency_not_self.lock" }

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
              name: "mydep/setup.cfg",
              content: fixture("setup_files", "setup.cfg")
            )
          end
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("requirements", "pbr.txt")
            )
          end

          it "updates the dependency" do
            expect(json_lockfile["default"]["requests"]["version"]).
              to eq("==2.18.4")
          end
        end

        context "that imports its own setup.py" do
          let(:dependency_files) do
            [pipfile, lockfile, setupfile, setup_cfg, requirements_file]
          end
          let(:pipfile_fixture_name) { "path_dependency" }
          let(:lockfile_fixture_name) { "path_dependency.lock" }
          let(:setupfile) do
            Dependabot::DependencyFile.new(
              name: "setup.py",
              content: fixture("setup_files", setupfile_fixture_name)
            )
          end
          let(:setupfile_fixture_name) { "with_pbr.py" }
          let(:setup_cfg) do
            Dependabot::DependencyFile.new(
              name: "setup.cfg",
              content: fixture("setup_files", "setup.cfg")
            )
          end
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("requirements", "pbr.txt")
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
              "requirements",
              "hard_names_runtime.txt"
            )
          )
        end

        it "updates the lockfile and the requirements.txt", :slow do
          expect(updated_files.map(&:name)).
            to match_array(%w(Pipfile.lock requirements.txt))

          updated_lock = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_txt = updated_files.find { |f| f.name == "requirements.txt" }

          JSON.parse(updated_lock.content).fetch("default").each do |nm, hash|
            expect(updated_txt.content).to include("#{nm}#{hash['version']}")
          end
        end

        context "because there are no runtime dependencies" do
          let(:pipfile_fixture_name) { "only_dev" }
          let(:lockfile_fixture_name) { "only_dev.lock" }
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "runtime.txt",
              content: fixture(
                "requirements",
                "version_not_specified_runtime.txt"
              )
            )
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "pytest",
              version: "3.3.1",
              previous_version: "3.2.3",
              package_manager: "pip",
              requirements: [{
                requirement: "*",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }],
              previous_requirements: [{
                requirement: "*",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }]
            )
          end

          it "does not update the requirements.txt" do
            expect(updated_files.map(&:name)).to eq(["Pipfile.lock"])
          end
        end
      end

      context "that looks like the output of `pipenv lock -r -d`" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "req-dev.txt",
            content: fixture(
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
            content: fixture("requirements", "pbr.txt")
          )
        end

        it "updates the lockfile only" do
          expect(updated_files.map(&:name)).to match_array(%w(Pipfile.lock))
        end
      end
    end
  end
end
