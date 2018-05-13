# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Python::Pip do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      content: fixture("python", "requirements", requirements_fixture_name),
      name: "requirements.txt"
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      requirements: [
        {
          file: "requirements.txt",
          requirement: "==2.8.1",
          groups: [],
          source: nil
        }
      ],
      previous_requirements: [
        {
          file: "requirements.txt",
          requirement: "==2.7.1",
          groups: [],
          source: nil
        }
      ],
      package_manager: "pip"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated requirements_file" do
      subject(:updated_requirements_file) do
        updated_files.find { |f| f.name == "requirements.txt" }
      end

      its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      its(:content) { is_expected.to include "luigi==2.2.0\n" }

      context "when only the minor version is specified" do
        let(:requirements_fixture_name) { "minor_version_specified.txt" }
        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      end

      context "when a local version is specified" do
        let(:requirements_fixture_name) { "local_version.txt" }
        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      end

      context "when there is a comment" do
        let(:requirements_fixture_name) { "comments.txt" }
        its(:content) { is_expected.to include "psycopg2==2.8.1  # Comment!\n" }
      end

      context "when there are hashes" do
        let(:requirements_fixture_name) { "hashes.txt" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "pytest",
            version: "3.3.1",
            requirements: [
              {
                file: "requirements.txt",
                requirement: "==3.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_version: "3.2.3",
            previous_requirements: [
              {
                file: "requirements.txt",
                requirement: "==3.2.3",
                groups: [],
                source: nil
              }
            ],
            package_manager: "pip"
          )
        end

        its(:content) do
          is_expected.to eq(
            "pytest==3.3.1 "\
            "--hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc42ad7"\
            "331c9ad06d0efe4962  "\
            "--hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d64096"\
            "cebe79fb51ecb2eb93\n"
          )
        end

        context "using a sha512 algorithm" do
          let(:requirements_fixture_name) { "hashes_512.txt" }

          its(:content) do
            is_expected.to include(
              "pytest==3.3.1 "\
              "--hash=sha512:f190f9a8a8f55e9dbf311429eb86e023e096d5388e1c4216"\
              "fc8d833fbdec8fa67f67b89a174dfead663b34e5f5df124085825446297cf7"\
              "d9500527d9e8ddb15d  "\
              "--hash=sha512:f3d73e475dbfbcd9f218268caefeab86038dde4380fcf727"\
              "b3436847849e57309c14f6f9769e85502c6121dab354d20a1316e2e30249c0"\
              "a2b28e87d90f71e65e\n"
            )
          end
        end

        context "with linebreaks" do
          let(:requirements_fixture_name) { "hashes_multiline.txt" }

          its(:content) do
            is_expected.to eq(
              "pytest==3.3.1 \\\n"\
              "    --hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc4"\
              "2ad7331c9ad06d0efe4962 \\\n"\
              "    --hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d6"\
              "4096cebe79fb51ecb2eb93\n"
            )
          end
        end

        context "with a single hash" do
          let(:requirements_fixture_name) { "hashes_single.txt" }
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "flask-featureflags",
              version: "0.6",
              requirements: [
                {
                  file: "requirements.txt",
                  requirement: "==0.6",
                  groups: [],
                  source: nil
                }
              ],
              previous_version: "0.5",
              previous_requirements: [
                {
                  file: "requirements.txt",
                  requirement: "==0.5",
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "pip"
            )
          end

          its(:content) do
            is_expected.to eq(
              "flask-featureflags==0.6 \\\n"\
              "    --hash=sha256:fc8490e4e4c1eac03e306fade8ef4be3cddff6229"\
              "aaa3bb96466ede7d107b241\n"
            )
          end
        end
      end

      context "when there are unused lines" do
        let(:requirements_fixture_name) { "invalid_lines.txt" }
        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
        its(:content) { is_expected.to include "# This is just a comment" }
      end

      context "when the dependency is in a child requirement file" do
        let(:dependency_files) { [requirements, more_requirements] }
        let(:requirements_fixture_name) { "cascading.txt" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "psycopg2",
            version: "2.8.1",
            requirements: [
              {
                file: "more_requirements.txt",
                requirement: "==2.8.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "more_requirements.txt",
                requirement: "==2.7.1",
                groups: [],
                source: nil
              }
            ],
            package_manager: "pip"
          )
        end

        let(:more_requirements) do
          Dependabot::DependencyFile.new(
            content: fixture("python", "requirements", "version_specified.txt"),
            name: "more_requirements.txt"
          )
        end

        it "updates and returns the right file" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("psycopg2==2.8.1\n")
        end
      end
    end

    context "with only a setup.py" do
      subject(:updated_setup_file) do
        updated_files.find { |f| f.name == "setup.py" }
      end
      let(:dependency_files) { [setup] }
      let(:setup) do
        Dependabot::DependencyFile.new(
          content: fixture("python", "setup_files", "setup.py"),
          name: "setup.py"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "psycopg2",
          version: "2.8.1",
          requirements: [
            {
              file: "setup.py",
              requirement: "==2.8.1",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "setup.py",
              requirement: "==2.7.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end

      its(:content) { is_expected.to include "'psycopg2==2.8.1',\n" }
      its(:content) { is_expected.to include "pep8==1.7.0" }

      context "with non-standard formatting" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "raven",
            version: "5.34.0",
            requirements: [
              {
                file: "setup.py",
                requirement: "==5.34.0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "setup.py",
                requirement: "==5.32.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "pip"
          )
        end

        # It would be nice to preserve the formatting (which should be
        # 'raven == 5.34.0') but it's no big deal.
        its(:content) { is_expected.to include "'raven ==5.34.0',\n" }
      end

      context "with a prefix-matcher" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: nil,
            requirements: [
              {
                file: "setup.py",
                requirement: "==2.13.*",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "setup.py",
                requirement: "==2.12.*",
                groups: [],
                source: nil
              }
            ],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "'requests==2.13.*',\n" }
      end

      context "with a range requirement" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "flake8",
            version: nil,
            requirements: [
              {
                file: "setup.py",
                requirement: ">2.5.4,<3.4.0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "setup.py",
                requirement: ">2.5.4,<3.0.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "'flake8 >2.5.4,<3.4.0',\n" }
      end
    end

    context "when the dependency is in constraints.txt and requirement.txt" do
      let(:dependency_files) { [requirements, constraints] }
      let(:requirements_fixture_name) { "specific_with_constraints.txt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.8.1",
          requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.8.1",
              groups: [],
              source: nil
            },
            {
              file: "constraints.txt",
              requirement: "==2.8.1",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.4.1",
              groups: [],
              source: nil
            },
            {
              file: "constraints.txt",
              requirement: "==2.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end

      let(:constraints) do
        Dependabot::DependencyFile.new(
          content: fixture("python", "constraints", "specific.txt"),
          name: "constraints.txt"
        )
      end

      it "updates both files" do
        expect(updated_files.map(&:name)).
          to match_array(%w(requirements.txt constraints.txt))
        expect(updated_files.first.content).to include("requests==2.8.1\n")
        expect(updated_files.last.content).to include("requests==2.8.1\n")
      end
    end

    context "with a Pipfile and Pipfile.lock" do
      let(:dependency_files) { [pipfile, lockfile] }

      let(:pipfile) do
        Dependabot::DependencyFile.new(content: pipfile_body, name: "Pipfile")
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          content: lockfile_body,
          name: "Pipfile.lock"
        )
      end
      let(:pipfile_body) do
        fixture("python", "pipfiles", "version_not_specified")
      end
      let(:lockfile_body) do
        fixture("python", "lockfiles", "version_not_specified.lock")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [
            {
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end
      let(:dependency_name) { "requests" }

      it "doesn't store the files permanently" do
        expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
      end

      it "returns DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end

      context "when the Pipfile hasn't changed" do
        let(:pipfile_body) do
          fixture("python", "pipfiles", "version_not_specified")
        end
        let(:lockfile_body) do
          fixture("python", "lockfiles", "version_not_specified.lock")
        end

        it "only returns the lockfile" do
          expect(updated_files.map(&:name)).to eq(["Pipfile.lock"])
        end
      end

      context "when the Pipfile specified a Python version" do
        let(:pipfile_body) { fixture("python", "pipfiles", "required_python") }
        let(:lockfile_body) do
          fixture("python", "lockfiles", "required_python.lock")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: "2.18.4",
            previous_version: "2.18.0",
            package_manager: "pip",
            requirements: [
              {
                requirement: "==2.18.4",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }
            ],
            previous_requirements: [
              {
                requirement: "==2.18.0",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }
            ]
          )
        end

        it "updates both files correctly" do
          expect(updated_files.map(&:name)).to eq(%w(Pipfile Pipfile.lock))

          updated_lockfile = updated_files.find { |f| f.name == "Pipfile.lock" }
          updated_pipfile = updated_files.find { |f| f.name == "Pipfile" }
          json_lockfile = JSON.parse(updated_lockfile.content)

          expect(updated_pipfile.content).
            to include('python_full_version = "2.7.14"')
          expect(json_lockfile["default"]["requests"]["version"]).
            to eq("==2.18.4")
          expect(json_lockfile["develop"]["pytest"]["version"]).to eq("==3.4.0")
          expect(json_lockfile["_meta"]["requires"]).
            to eq(JSON.parse(lockfile_body)["_meta"]["requires"])
          expect(json_lockfile["develop"]["funcsigs"]["markers"]).
            to eq("python_version < '3.0'")
        end
      end

      context "when the Pipfile included an environment variable source" do
        let(:pipfile_body) do
          fixture("python", "pipfiles", "environment_variable_source")
        end
        let(:lockfile_body) do
          fixture("python", "lockfiles", "environment_variable_source.lock")
        end
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
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
            requirements: [
              {
                requirement: "==2.18.4",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }
            ],
            previous_requirements: [
              {
                requirement: "==2.18.0",
                file: "Pipfile",
                source: nil,
                groups: ["default"]
              }
            ]
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
            to eq(JSON.parse(lockfile_body)["_meta"]["hash"])
        end

        describe "with dependency names that need to be normalised" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "requests",
              version: "2.18.4",
              previous_version: "2.18.0",
              package_manager: "pip",
              requirements: [
                {
                  requirement: "==2.18.4",
                  file: "Pipfile",
                  source: nil,
                  groups: ["default"]
                }
              ],
              previous_requirements: [
                {
                  requirement: "==2.18.0",
                  file: "Pipfile",
                  source: nil,
                  groups: ["default"]
                }
              ]
            )
          end
          let(:pipfile_body) { fixture("python", "pipfiles", "hard_names") }
          let(:lockfile_body) do
            fixture("python", "lockfiles", "hard_names.lock")
          end

          it "updates only what it needs to" do
            expect(json_lockfile["default"]["requests"]["version"]).
              to eq("==2.18.4")
            expect(json_lockfile["develop"]["pytest"]["version"]).
              to eq("==3.4.0")
          end
        end

        describe "with a subdependency from an extra" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "raven",
              version: "6.7.0",
              previous_version: "5.27.1",
              package_manager: "pip",
              requirements: [
                {
                  requirement: "==6.7.0",
                  file: "Pipfile",
                  source: nil,
                  groups: ["default"]
                }
              ],
              previous_requirements: [
                {
                  requirement: "==5.27.1",
                  file: "Pipfile",
                  source: nil,
                  groups: ["default"]
                }
              ]
            )
          end
          let(:pipfile_body) do
            fixture("python", "pipfiles", "extra_subdependency")
          end
          let(:lockfile_body) do
            fixture("python", "lockfiles", "extra_subdependency.lock")
          end

          it "doesn't remove the subdependency" do
            expect(json_lockfile["default"]["raven"]["version"]).
              to eq("==6.7.0")
            expect(json_lockfile["default"]["blinker"]["version"]).
              to eq("==1.4")
          end
        end
      end
    end
  end

  describe "#updated_pipfile_content" do
    subject(:updated_pipfile_content) { updater.send(:updated_pipfile_content) }

    let(:dependency_files) { [pipfile, lockfile] }
    let(:pipfile) do
      Dependabot::DependencyFile.new(content: pipfile_body, name: "Pipfile")
    end
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        content: lockfile_body,
        name: "Pipfile.lock"
      )
    end
    let(:pipfile_body) do
      fixture("python", "pipfiles", "version_not_specified")
    end
    let(:lockfile_body) do
      fixture("python", "lockfiles", "version_not_specified.lock")
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "2.18.4",
        previous_version: "2.18.0",
        package_manager: "pip",
        requirements: [
          {
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }
        ],
        previous_requirements: [
          {
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }
        ]
      )
    end
    let(:dependency_name) { "requests" }

    context "with single quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python-decouple",
          version: "3.2",
          previous_version: "3.1",
          package_manager: "pip",
          requirements: [
            {
              requirement: "==3.2",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==3.1",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end

      it { is_expected.to include(%q('python_decouple' = "==3.2")) }
    end

    context "with double quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.18.4",
          previous_version: "2.18.0",
          package_manager: "pip",
          requirements: [
            {
              requirement: "==2.18.4",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end

      it { is_expected.to include('"requests" = "==2.18.4"') }
    end

    context "without quotes" do
      let(:pipfile_body) { fixture("python", "pipfiles", "with_quotes") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pytest",
          version: "3.3.1",
          previous_version: "3.2.3",
          package_manager: "pip",
          requirements: [
            {
              requirement: "==3.3.1",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==3.2.3",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }
          ]
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
          requirements: [
            {
              requirement: "==2.18.4",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ],
          previous_requirements: [
            {
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }
          ]
        )
      end
      let(:pipfile_body) { fixture("python", "pipfiles", "hard_names") }
      let(:lockfile_body) { fixture("python", "lockfiles", "hard_names.lock") }

      it { is_expected.to include('Requests = "==2.18.4"') }
    end
  end
end
