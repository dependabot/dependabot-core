# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pipfile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::RequirementFileUpdater do
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
      content: fixture("requirements", requirements_fixture_name),
      name: "requirements.txt"
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      requirements: [{
        file: "requirements.txt",
        requirement: updated_requirement_string,
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "requirements.txt",
        requirement: previous_requirement_string,
        groups: [],
        source: nil
      }],
      package_manager: "pip"
    )
  end
  let(:previous_requirement_string) { "==2.6.1" }
  let(:updated_requirement_string) { "==2.8.1" }
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
      # extras are preserved
      its(:content) { is_expected.to include "aiocache[redis]==0.10.0\n" }

      context "when only the minor version is specified" do
        let(:requirements_fixture_name) { "minor_version_specified.txt" }
        let(:previous_requirement_string) { "==2.6" }

        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      end

      context "when a local version is specified" do
        let(:requirements_fixture_name) { "local_version.txt" }
        let(:previous_requirement_string) { "==2.6.1+gc.1" }

        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      end

      context "when there is a comment" do
        let(:requirements_fixture_name) { "comments.txt" }
        let(:previous_requirement_string) { "==2.6.1" }

        its(:content) { is_expected.to include "psycopg2==2.8.1  # Comment!\n" }
      end

      context "with an unknown package" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "some_unknown_package",
            version: "24.3.3",
            requirements: [{
              file: "requirements.txt",
              requirement: updated_requirement_string,
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "requirements.txt",
              requirement: previous_requirement_string,
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        let(:requirements_fixture_name) { "hashes_unknown_package.txt" }
        let(:previous_requirement_string) { "==24.3.3" }
        let(:updated_requirement_string) { "==24.4.0" }

        context "when package is not in default index" do
          it "raises an error" do
            expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end

        context "when package is in default index" do
          before do
            allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
              .and_return([{ "hash" => "1234567890abcdef" }])
          end

          its(:content) do
            is_expected.to include "some_unknown_package==24.4.0"
            is_expected.to include "--hash=sha256:1234567890abcdef"
          end
        end
      end

      context "when there is a range" do
        context "with a space after the comma" do
          let(:requirements_fixture_name) { "version_between_bounds.txt" }
          let(:previous_requirement_string) { "<=3.0.0,==2.6.1" }
          let(:updated_requirement_string) { "==2.8.1,<=3.0.0" }

          its(:content) { is_expected.to include "psycopg2==2.8.1, <=3.0.0\n" }
        end

        context "with no space after the comma" do
          let(:requirements) do
            Dependabot::DependencyFile.new(
              content: fixture("requirements", "version_between_bounds.txt")
                       .gsub(", ", ","),
              name: "requirements.txt"
            )
          end
          let(:previous_requirement_string) { "<=3.0.0,==2.6.1" }
          let(:updated_requirement_string) { "==2.8.1,<=3.0.0" }

          its(:content) { is_expected.to include "psycopg2==2.8.1,<=3.0.0\n" }
        end
      end

      context "with substring names" do
        let(:requirements_fixture_name) { "name_clash.txt" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "sqlalchemy",
            version: "1.2.10",
            requirements: [{
              file: "requirements.txt",
              requirement: "==1.2.10",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "requirements.txt",
              requirement: "==1.2.9",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "\nSQLAlchemy==1.2.10\n" }
        its(:content) { is_expected.to include "Flask-SQLAlchemy==1.2.9\n" }
      end

      context "when there are hashes" do
        let(:requirements_fixture_name) { "hashes.txt" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "pytest",
            version: "3.3.1",
            requirements: [{
              file: "requirements.txt",
              requirement: "==3.3.1",
              groups: [],
              source: nil
            }],
            previous_version: "3.2.3",
            previous_requirements: [{
              file: "requirements.txt",
              requirement: "==3.2.3",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) do
          is_expected.to eq(
            "pytest==3.3.1 " \
            "--hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc42ad7" \
            "331c9ad06d0efe4962  " \
            "--hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d64096" \
            "cebe79fb51ecb2eb93\n"
          )
        end

        context "when using a sha512 algorithm" do
          let(:requirements_fixture_name) { "hashes_512.txt" }

          its(:content) do
            is_expected.to include(
              "pytest==3.3.1 " \
              "--hash=sha512:f190f9a8a8f55e9dbf311429eb86e023e096d5388e1c4216" \
              "fc8d833fbdec8fa67f67b89a174dfead663b34e5f5df124085825446297cf7" \
              "d9500527d9e8ddb15d  " \
              "--hash=sha512:f3d73e475dbfbcd9f218268caefeab86038dde4380fcf727" \
              "b3436847849e57309c14f6f9769e85502c6121dab354d20a1316e2e30249c0" \
              "a2b28e87d90f71e65e\n"
            )
          end
        end

        context "with linebreaks" do
          let(:requirements_fixture_name) { "hashes_multiline.txt" }

          its(:content) do
            is_expected.to eq(
              "pytest==3.3.1 \\\n" \
              "    --hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc4" \
              "2ad7331c9ad06d0efe4962 \\\n" \
              "    --hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d6" \
              "4096cebe79fb51ecb2eb93\n"
            )
          end
        end

        context "with linebreaks and no space after each hash" do
          let(:requirements_fixture_name) { "hashes_multiline_no_space.txt" }

          its(:content) do
            is_expected.to eq(
              "pytest==3.3.1 \\\n" \
              "    --hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc4" \
              "2ad7331c9ad06d0efe4962\\\n" \
              "    --hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d6" \
              "4096cebe79fb51ecb2eb93\n"
            )
          end
        end

        context "with markers and linebreaks" do
          let(:requirements_fixture_name) { "markers_and_hashes_multiline.txt" }

          its(:content) do
            is_expected.to eq(
              "pytest==3.3.1 ; python_version=='2.7' \\\n" \
              "    --hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc4" \
              "2ad7331c9ad06d0efe4962 \\\n" \
              "    --hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d6" \
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
              requirements: [{
                file: "requirements.txt",
                requirement: "==0.6",
                groups: [],
                source: nil
              }],
              previous_version: "0.5",
              previous_requirements: [{
                file: "requirements.txt",
                requirement: "==0.5",
                groups: [],
                source: nil
              }],
              package_manager: "pip"
            )
          end

          its(:content) do
            is_expected.to eq(
              "flask-featureflags==0.6 \\\n" \
              "    --hash=sha256:fc8490e4e4c1eac03e306fade8ef4be3cddff6229" \
              "aaa3bb96466ede7d107b241\n"
            )
          end

          context "when moving to multiple hashes" do
            let(:requirements_fixture_name) { "hashes_single_to_multiple.txt" }
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "pytest",
                version: "3.3.1",
                requirements: [{
                  file: "requirements.txt",
                  requirement: "==3.3.1",
                  groups: [],
                  source: nil
                }],
                previous_version: "3.2.3",
                previous_requirements: [{
                  file: "requirements.txt",
                  requirement: "==3.2.3",
                  groups: [],
                  source: nil
                }],
                package_manager: "pip"
              )
            end

            its(:content) do
              is_expected.to eq(
                "pytest==3.3.1 " \
                "--hash=sha256:ae4a2d0bae1098bbe938ecd6c20a526d5d47a94dc4" \
                "2ad7331c9ad06d0efe4962 " \
                "--hash=sha256:cf8436dc59d8695346fcd3ab296de46425ecab00d6" \
                "4096cebe79fb51ecb2eb93\n"
              )
            end
          end
        end
      end

      context "when there are unused lines" do
        let(:requirements_fixture_name) { "invalid_lines.txt" }
        let(:previous_requirement_string) { "==2.6.1" }

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
            requirements: [{
              file: "more_requirements.txt",
              requirement: "==2.8.1",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "more_requirements.txt",
              requirement: "==2.6.1",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        let(:more_requirements) do
          Dependabot::DependencyFile.new(
            content: fixture("requirements", "version_specified.txt"),
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
          content: fixture("setup_files", "setup.py"),
          name: "setup.py"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "psycopg2",
          version: "2.8.1",
          requirements: [{
            file: "setup.py",
            requirement: "==2.8.1",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "setup.py",
            requirement: "==2.6.1",
            groups: [],
            source: nil
          }],
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
            requirements: [{
              file: "setup.py",
              requirement: "==5.34.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.py",
              requirement: "==5.32.0",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "'raven == 5.34.0',\n" }
      end

      context "with a prefix-matcher" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: nil,
            requirements: [{
              file: "setup.py",
              requirement: "==2.13.*",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.py",
              requirement: "==2.12.*",
              groups: [],
              source: nil
            }],
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
            requirements: [{
              file: "setup.py",
              requirement: ">2.5.4,<3.4.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.py",
              requirement: "<3.0.0,>2.5.4",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "'flake8 > 2.5.4, < 3.4.0',\n" }
      end
    end

    context "with only a setup.cfg" do
      subject(:updated_setup_cfg_file) do
        updated_files.find { |f| f.name == "setup.cfg" }
      end

      let(:dependency_files) { [setup_cfg] }
      let(:setup_cfg) do
        Dependabot::DependencyFile.new(
          content: fixture("setup_files", "setup_with_requires.cfg"),
          name: "setup.cfg"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "psycopg2",
          version: "2.8.1",
          requirements: [{
            file: "setup.cfg",
            requirement: "==2.8.1",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "setup.cfg",
            requirement: "==2.6.1",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      its(:content) { is_expected.to include "pep8==1.7.0" }

      context "with non-standard formatting" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "raven",
            version: "5.34.0",
            requirements: [{
              file: "setup.cfg",
              requirement: "==5.34.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.cfg",
              requirement: "==5.32.0",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "raven == 5.34.0\n" }
      end

      context "with a prefix-matcher" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: nil,
            requirements: [{
              file: "setup.cfg",
              requirement: "==2.13.*",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.cfg",
              requirement: "==2.12.*",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "requests==2.13.*\n" }
      end

      context "with a range requirement" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "flake8",
            version: nil,
            requirements: [{
              file: "setup.cfg",
              requirement: ">2.5.4,<3.4.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "setup.cfg",
              requirement: "<3.0.0,>2.5.4",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        its(:content) { is_expected.to include "flake8 > 2.5.4, < 3.4.0\n" }
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
          content: fixture("constraints", "specific.txt"),
          name: "constraints.txt"
        )
      end

      it "updates both files" do
        expect(updated_files.map(&:name))
          .to match_array(%w(requirements.txt constraints.txt))
        expect(updated_files.first.content).to include("requests==2.8.1\n")
        expect(updated_files.last.content).to include("requests==2.8.1\n")
      end
    end
  end
end
