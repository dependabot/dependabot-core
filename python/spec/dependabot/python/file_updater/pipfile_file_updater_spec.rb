# typed: false
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
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end
  let(:dependency_files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfile_files", pipfile_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("pipfile_files", lockfile_fixture_name)
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
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:repo_contents_path) { nil }

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

        expect(json_lockfile["default"]["requests"]["version"])
          .to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"])
          .to eq("==3.4.0")
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

        expect(updated_pipfile.content)
          .to include('python_full_version = "3.9.4"')
        expect(json_lockfile["default"]["requests"]["version"])
          .to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
        expect(json_lockfile["_meta"]["requires"])
          .to eq(JSON.parse(lockfile.content)["_meta"]["requires"])
      end

      context "when from a Poetry file and including || logic" do
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

      context "when including a .python-version file" do
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

    context "with a source not included in the original Pipfile" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.posrip.com/pypi/"
            }
          )
        ]
      end

      it "the source is not included in the final updated files" do
        expect(updated_files.map(&:name)).to eq(%w(Pipfile.lock)) # because Pipfile shouldn't have changed

        updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
        expect(updated_lockfile.content).not_to include("dependabot-inserted-index")
        expect(updated_lockfile.content).not_to include("https://pypi.posrip.com/pypi/")

        json_lockfile = JSON.parse(updated_lockfile.content)
        expect(json_lockfile["_meta"]["sources"]).to eq(JSON.parse(lockfile.content)["_meta"]["sources"])
      end
    end

    context "when the Pipfile included an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.org/simple"
            }
          )
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

        expect(updated_pipfile.content)
          .to include("pypi.org/${ENV_VAR}")
        expect(json_lockfile["default"]["requests"]["version"])
          .to eq("==2.18.4")
        expect(json_lockfile["_meta"]["sources"])
          .to eq(
            [{ "url" => "https://pypi.org/${ENV_VAR}",
               "verify_ssl" => true }]
          )
        expect(updated_lockfile.content)
          .not_to include("pypi.org/simple")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
      end
    end

    describe "the updated Pipfile.lock" do
      let(:updated_lockfile) do
        updated_files.find { |f| f.name == "Pipfile.lock" }
      end

      let(:json_lockfile) { JSON.parse(updated_lockfile.content) }

      it "updates only what it needs to" do
        expect(json_lockfile["default"]["requests"]["version"])
          .to eq("==2.18.4")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.2.3")
        expect(json_lockfile["_meta"]["hash"])
          .to eq(JSON.parse(lockfile.content)["_meta"]["hash"])
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
          expect(json_lockfile["default"].key?("py")).to be(false)
          expect(json_lockfile["develop"]["py"]["version"]).to eq("==1.7.0")
          expect(json_lockfile["_meta"]["hash"])
            .to eq(JSON.parse(lockfile.content)["_meta"]["hash"])
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
          expect(json_lockfile["default"]["blinker"]).to have_key("version")
        end
      end

      context "with a git dependency" do
        let(:pipfile_fixture_name) { "git_source_no_ref" }
        let(:lockfile_fixture_name) { "git_source_no_ref.lock" }

        context "when updating the non-git dependency" do
          it "doesn't update the git dependency" do
            expect(json_lockfile["default"]["requests"]["version"])
              .to eq("==2.18.4")
            expect(json_lockfile["default"]["pythonfinder"])
              .to eq(JSON.parse(lockfile.content)["default"]["pythonfinder"])
          end
        end
      end

      context "with a path dependency" do
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
          expect(json_lockfile["default"]["requests"]["version"])
            .to eq("==2.18.4")
        end

        context "when needing to be sanitized" do
          let(:setupfile_fixture_name) { "small_needs_sanitizing.py" }

          it "updates the dependency" do
            expect(json_lockfile["default"]["requests"]["version"])
              .to eq("==2.18.4")
          end
        end

        context "when importing a setup.cfg" do
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
            expect(json_lockfile["default"]["requests"]["version"])
              .to eq("==2.18.4")
          end
        end

        context "when importing its own setup.py" do
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
            expect(json_lockfile["default"]["requests"]["version"])
              .to eq("==2.18.4")
          end
        end
      end

      context "with a python library setup as an editable dependency that needs extra files" do
        let(:project_name) { "pipenv/editable-package" }
        let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
        let(:dependency_files) do
          %w(Pipfile Pipfile.lock pyproject.toml).map do |name|
            Dependabot::DependencyFile.new(
              name: name,
              content: fixture("projects", project_name, name)
            )
          end
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "cryptography",
            version: "41.0.5",
            previous_version: "40.0.1",
            package_manager: "pip",
            requirements: [{
              requirement: "==41.0.5",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }],
            previous_requirements: [{
              requirement: "==40.0.1",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          )
        end

        it "updates the dependency" do
          expect(json_lockfile["develop"]["cryptography"]["version"])
            .to eq("==41.0.5")
        end
      end
    end

    context "when the Pipfile included an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_verify_ssl_false" }
      let(:lockfile_fixture_name) { "environment_variable_verify_ssl_false.lock" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.org/simple"
            }
          )
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

        expect(updated_pipfile.content)
          .to include("pypi.org/${ENV_VAR}")
        expect(json_lockfile["default"]["requests"]["version"])
          .to eq("==2.18.4")
        expect(json_lockfile["_meta"]["sources"])
          .to eq(
            [{ "url" => "https://pypi.org/${ENV_VAR}",
               "verify_ssl" => true }]
          )
        expect(updated_lockfile.content)
          .not_to include("pypi.org/simple")
        expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
      end
    end

    context "when the Pipfile is unresolvable" do
      let(:pipfile_fixture_name) { "malformed_pipfile_source_missing" }
      let(:lockfile_fixture_name) { "malformed_pipfile_source_missing.lock" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://pypi.org/simple"
            }
          )
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

      it "raise DependencyFileNotResolvable error" do
        expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a requirements.txt" do
      let(:dependency_files) { [pipfile, lockfile, requirements_file] }

      context "when the output looks like `pipenv requirements`" do
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

        it "updates the lockfile and the requirements.txt" do
          expect(updated_files.map(&:name))
            .to match_array(%w(Pipfile.lock requirements.txt))

          updated_lock = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_txt = updated_files.find { |f| f.name == "requirements.txt" }

          JSON.parse(updated_lock.content).fetch("default").each do |nm, hash|
            expect(updated_txt.content).to include("#{nm}#{hash['version']}")
          end
        end

        context "when there are no runtime dependencies" do
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

      context "when the output looks like `pipenv requirements --dev`" do
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
          expect(updated_files.map(&:name))
            .to match_array(%w(Pipfile.lock req-dev.txt))

          updated_lock = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_txt = updated_files.find { |f| f.name == "req-dev.txt" }

          JSON.parse(updated_lock.content).fetch("develop").each do |nm, hash|
            expect(updated_txt.content).to include("#{nm}#{hash['version']}")
          end
        end
      end

      context "when unrelated" do
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

    describe "preserving extras information" do
      context "when a dependency has extras in the original lockfile" do
        let(:dependency_name) { "psycopg" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "psycopg",
            version: "3.2.10",
            previous_version: "3.2.3",
            package_manager: "pip",
            requirements: [{
              requirement: "==3.2.10",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }],
            previous_requirements: [{
              requirement: "==3.2.3",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          )
        end

        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: <<~PIPFILE
              [[source]]
              name = "pypi"
              url = "https://pypi.org/simple"
              verify_ssl = true

              [packages]
              psycopg = {extras = ["binary"], version = "==3.2.3"}

              [dev-packages]

              [requires]
              python_version = "3.9.13"
            PIPFILE
          )
        end

        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile.lock",
            content: <<~LOCKFILE
              {
                  "_meta": {
                      "hash": {
                          "sha256": "a67e77742182039b1fc162fe41efb0c892133af3230bda467060a301a1f02bd5"
                      },
                      "pipfile-spec": 6,
                      "requires": {
                          "python_version": "3.9.13"
                      },
                      "sources": [
                          {
                              "name": "pypi",
                              "url": "https://pypi.org/simple",
                              "verify_ssl": true
                          }
                      ]
                  },
                  "default": {
                      "psycopg": {
                          "extras": [
                              "binary"
                          ],
                          "hashes": [
                              "sha256:old_hash_1",
                              "sha256:old_hash_2"
                          ],
                          "index": "pypi",
                          "markers": "python_version >= '3.8'",
                          "version": "==3.2.3"
                      },
                      "psycopg-binary": {
                          "hashes": [
                              "sha256:binary_hash_1",
                              "sha256:binary_hash_2"
                          ],
                          "markers": "python_version >= '3.8'",
                          "version": "==3.2.3"
                      }
                  },
                  "develop": {}
              }
            LOCKFILE
          )
        end

        it "preserves extras in the updated lockfile" do
          expect(updated_files.map(&:name)).to match_array(%w(Pipfile Pipfile.lock))

          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          # Check that the version was updated
          expect(json_lockfile["default"]["psycopg"]["version"]).to eq("==3.2.10")

          # Check that extras are preserved and appear first in the hash
          expect(json_lockfile["default"]["psycopg"]["extras"]).to eq(["binary"])
          expect(json_lockfile["default"]["psycopg"].keys.first).to eq("extras")

          # Check that the Pipfile was also updated
          expect(updated_pipfile.content).to include('version = "==3.2.10"')
          expect(updated_pipfile.content).to include('extras = ["binary"]')
        end

        it "places extras as the first key in the dependency hash" do
          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)
          psycopg_keys = json_lockfile["default"]["psycopg"].keys

          expect(psycopg_keys.first).to eq("extras")
        end
      end

      context "when dependency has extras in develop section" do
        let(:dependency_name) { "pytest" }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: <<~PIPFILE
              [[source]]
              name = "pypi"
              url = "https://pypi.org/simple"
              verify_ssl = true

              [packages]

              [dev-packages]
              pytest = {extras = ["coverage"], version = "==6.0.0"}

              [requires]
              python_version = "3.9"
            PIPFILE
          )
        end

        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile.lock",
            content: <<~LOCKFILE
              {
                  "_meta": {
                      "hash": {
                          "sha256": "example_hash"
                      },
                      "pipfile-spec": 6,
                      "requires": {
                          "python_version": "3.9"
                      },
                      "sources": [
                          {
                              "name": "pypi",
                              "url": "https://pypi.org/simple",
                              "verify_ssl": true
                          }
                      ]
                  },
                  "default": {},
                  "develop": {
                      "pytest": {
                          "extras": [
                              "coverage"
                          ],
                          "hashes": [
                              "sha256:example_hash_1"
                          ],
                          "index": "pypi",
                          "version": "==6.0.0"
                      }
                  }
              }
            LOCKFILE
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "pytest",
            version: "6.2.0",
            previous_version: "6.0.0",
            package_manager: "pip",
            requirements: [{
              requirement: "==6.2.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }],
            previous_requirements: [{
              requirement: "==6.0.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          )
        end

        it "preserves extras in develop dependencies" do
          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          expect(json_lockfile["develop"]["pytest"]["extras"]).to eq(["coverage"])
          expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==6.2.0")
          expect(json_lockfile["develop"]["pytest"].keys.first).to eq("extras")
        end
      end

      context "when multiple dependencies have extras" do
        let(:dependency_name) { "psycopg" }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: <<~PIPFILE
              [[source]]
              name = "pypi"
              url = "https://pypi.org/simple"
              verify_ssl = true

              [packages]
              psycopg = {extras = ["binary"], version = "==3.2.3"}
              django = {extras = ["bcrypt"], version = "==3.0.0"}

              [dev-packages]
              pytest = {extras = ["coverage"], version = "==6.0.0"}

              [requires]
              python_version = "3.9"
            PIPFILE
          )
        end

        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile.lock",
            content: <<~LOCKFILE
              {
                  "_meta": {
                      "hash": {
                          "sha256": "example_hash"
                      },
                      "pipfile-spec": 6,
                      "requires": {
                          "python_version": "3.9"
                      },
                      "sources": [
                          {
                              "name": "pypi",
                              "url": "https://pypi.org/simple",
                              "verify_ssl": true
                          }
                      ]
                  },
                  "default": {
                      "psycopg": {
                          "extras": [
                              "binary"
                          ],
                          "hashes": [
                              "sha256:example_hash_1"
                          ],
                          "index": "pypi",
                          "version": "==3.2.3"
                      },
                      "django": {
                          "extras": [
                              "bcrypt"
                          ],
                          "hashes": [
                              "sha256:example_hash_2"
                          ],
                          "index": "pypi",
                          "version": "==3.0.0"
                      }
                  },
                  "develop": {
                      "pytest": {
                          "extras": [
                              "coverage"
                          ],
                          "hashes": [
                              "sha256:example_hash_3"
                          ],
                          "index": "pypi",
                          "version": "==6.0.0"
                      }
                  }
              }
            LOCKFILE
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "psycopg",
            version: "3.2.10",
            previous_version: "3.2.3",
            package_manager: "pip",
            requirements: [{
              requirement: "==3.2.10",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }],
            previous_requirements: [{
              requirement: "==3.2.3",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          )
        end

        it "preserves extras for all dependencies, only updating the target dependency" do
          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          # Updated dependency should have preserved extras and new version
          expect(json_lockfile["default"]["psycopg"]["extras"]).to eq(["binary"])
          expect(json_lockfile["default"]["psycopg"]["version"]).to eq("==3.2.10")
          expect(json_lockfile["default"]["psycopg"].keys.first).to eq("extras")

          # Other dependencies should remain unchanged with preserved extras
          expect(json_lockfile["default"]["django"]["extras"]).to eq(["bcrypt"])
          expect(json_lockfile["default"]["django"]["version"]).to eq("==3.0.0")
          expect(json_lockfile["default"]["django"].keys.first).to eq("extras")

          expect(json_lockfile["develop"]["pytest"]["extras"]).to eq(["coverage"])
          expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==6.0.0")
          expect(json_lockfile["develop"]["pytest"].keys.first).to eq("extras")
        end
      end

      context "when the same dependency exists in both default and develop sections" do
        let(:dependency_name) { "pytest" }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: <<~PIPFILE
              [[source]]
              name = "pypi"
              url = "https://pypi.org/simple"
              verify_ssl = true

              [packages]
              pytest = "==6.0.0"

              [dev-packages]
              pytest = {extras = ["coverage"], version = "==6.0.0"}

              [requires]
              python_version = "3.9"
            PIPFILE
          )
        end

        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile.lock",
            content: <<~LOCKFILE
              {
                  "_meta": {
                      "hash": {
                          "sha256": "example_hash"
                      },
                      "pipfile-spec": 6,
                      "requires": {
                          "python_version": "3.9"
                      },
                      "sources": [
                          {
                              "name": "pypi",
                              "url": "https://pypi.org/simple",
                              "verify_ssl": true
                          }
                      ]
                  },
                  "default": {
                      "pytest": {
                          "hashes": [
                              "sha256:default_hash_1"
                          ],
                          "index": "pypi",
                          "version": "==6.0.0"
                      }
                  },
                  "develop": {
                      "pytest": {
                          "extras": [
                              "coverage"
                          ],
                          "hashes": [
                              "sha256:develop_hash_1"
                          ],
                          "index": "pypi",
                          "version": "==6.0.0"
                      }
                  }
              }
            LOCKFILE
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "pytest",
            version: "6.2.0",
            previous_version: "6.0.0",
            package_manager: "pip",
            requirements: [{
              requirement: "==6.2.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }],
            previous_requirements: [{
              requirement: "==6.0.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          )
        end

        it "correctly scopes extras lookup to the specific section being updated" do
          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          # The develop section should be updated and preserve its extras
          expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==6.2.0")
          expect(json_lockfile["develop"]["pytest"]["extras"]).to eq(["coverage"])
          expect(json_lockfile["develop"]["pytest"].keys.first).to eq("extras")

          # The default section should remain unchanged and not have extras
          expect(json_lockfile["default"]["pytest"]["version"]).to eq("==6.0.0")
          expect(json_lockfile["default"]["pytest"]).not_to have_key("extras")
        end

        context "when updating the default section instead" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "pytest",
              version: "6.2.0",
              previous_version: "6.0.0",
              package_manager: "pip",
              requirements: [{
                requirement: "==6.2.0",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }],
              previous_requirements: [{
                requirement: "==6.0.0",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }]
            )
          end

          it "correctly updates the default section without affecting develop section" do
            updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
            json_lockfile = JSON.parse(updated_lockfile.content)

            # The default section should be updated and remain without extras
            expect(json_lockfile["default"]["pytest"]["version"]).to eq("==6.2.0")
            expect(json_lockfile["default"]["pytest"]).not_to have_key("extras")

            # The develop section should remain unchanged with its extras
            expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==6.0.0")
            expect(json_lockfile["develop"]["pytest"]["extras"]).to eq(["coverage"])
            expect(json_lockfile["develop"]["pytest"].keys.first).to eq("extras")
          end
        end
      end
    end
  end
end
