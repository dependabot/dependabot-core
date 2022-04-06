# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/python/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Python::FileParser do
  it_behaves_like "a dependency file parser"

  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      reject_external_code: reject_external_code
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:reject_external_code) { false }

  let(:files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: requirements_body
    )
  end
  let(:requirements_body) { fixture("requirements", requirements_fixture_name) }
  let(:requirements_fixture_name) { "version_specified.txt" }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(4) }

    context "with a version specified" do
      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with a .python-version file" do
      let(:files) { [requirements, python_version_file] }
      let(:python_version_file) do
        Dependabot::DependencyFile.new(
          name: ".python-version",
          content: "2.7.18\n"
        )
      end

      its(:length) { is_expected.to eq(4) }
    end

    context "with jinja templates" do
      let(:requirements_fixture_name) { "jinja_requirements.txt" }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with comments" do
      let(:requirements_fixture_name) { "comments.txt" }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with markers" do
      context "that include a < in the marker" do
        let(:requirements_fixture_name) { "markers.txt" }

        it "parses only the >= marker" do
          expect(dependencies.length).to eq(1)

          dependency = dependencies.first

          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("distro")
          expect(dependency.version).to eq("1.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==1.3.0",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      context "that include a < in the requirement" do
        let(:requirements_fixture_name) { "markers_2.txt" }

        it "parses only the >= marker" do
          expect(dependencies.length).to eq(1)

          dependency = dependencies.first

          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("cryptography")
          expect(dependency.version).to eq("2.7")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.7",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with extras" do
      let(:requirements_fixture_name) { "extras.txt" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2[bar,foo]")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with an 'unsafe' name" do
      let(:requirements_body) { "mypy_extensions==0.2.0" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "normalises the name" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mypy-extensions")
        end
      end
    end

    context "with invalid lines" do
      let(:requirements_fixture_name) { "invalid_lines.txt" }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with tarball path dependencies" do
      let(:files) { [pyproject, requirements, tarball_path_dependency] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("requirements", "tarball_path_dependency")
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "tarball_path_dependency.toml")
        )
      end
      let(:tarball_path_dependency) do
        Dependabot::DependencyFile.new(
          name: "taxtea-0.6.0.tar.gz",
          content: fixture("path_dependencies", "taxtea-0.6.0.tar.gz")
        )
      end

      describe "the first dependency" do
        it "has the right details" do
          expect(dependencies.map(&:name)).not_to match_array([])
        end
      end
    end

    context "that requires itself" do
      let(:files) { [requirements] }
      let(:requirements_fixture_name) { "cascading.txt" }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "more_requirements.txt",
          content: requirements_body
        )
      end

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with an invalid value" do
      let(:requirements_fixture_name) { "invalid_value.txt" }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with invalid options" do
      let(:requirements_fixture_name) { "invalid_options.txt" }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with invalid requirements" do
      let(:requirements_fixture_name) { "invalid_requirements.txt" }

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with no version specified" do
      let(:requirements_fixture_name) { "version_not_specified.txt" }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to be_nil
          expect(dependency.requirements.first[:requirement]).to be_nil
        end
      end
    end

    context "with prefix matching specified" do
      let(:requirements_fixture_name) { "prefix_match.txt" }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to be_nil
          expect(dependency.requirements.first[:requirement]).to eq("==2.6.*")
        end
      end
    end

    context "with a version specified as between two constraints" do
      let(:requirements_fixture_name) { "version_between_bounds.txt" }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to be_nil
          expect(dependency.requirements.first[:requirement]).
            to eq("<=3.0.0,==2.6.1")
        end
      end
    end

    context "with a git dependency" do
      let(:requirements_fixture_name) { "with_git_dependency.txt" }
      its(:length) { is_expected.to eq(1) }
    end

    context "with a constraints file" do
      let(:files) { [requirements, constraints] }
      let(:requirements_fixture_name) { "with_constraints.txt" }

      context "that aren't specific" do
        let(:constraints) do
          Dependabot::DependencyFile.new(
            name: "constraints.txt",
            content: fixture("constraints", "less_than.txt")
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to be_nil
            expect(dependency.requirements.map { |r| r[:requirement] }).
              to match_array(["<2.0.0", nil])
          end
        end
      end

      context "that are specific" do
        let(:constraints) do
          Dependabot::DependencyFile.new(
            name: "constraints.txt",
            content: fixture("constraints", "specific.txt")
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to eq("2.0.0")
            expect(dependency.requirements).to match_array(
              [{
                requirement: nil,
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "==2.0.0",
                file: "constraints.txt",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        context "when the requirements file is specific, too" do
          let(:requirements_fixture_name) { "specific_with_constraints.txt" }
          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("requests")
              expect(dependency.version).to eq("2.0.0")
              expect(dependency.requirements).to match_array(
                [{
                  requirement: "==2.0.0",
                  file: "constraints.txt",
                  groups: ["dependencies"],
                  source: nil
                }, {
                  requirement: "==2.4.1",
                  file: "requirements.txt",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end
    end

    context "with requirements-dev.txt" do
      let(:file) { [requirements] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements-dev.txt",
          content: fixture("requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(4) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements-dev.txt",
              groups: ["dev-dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with dev-requirements.txt" do
      let(:file) { [requirements] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "dev-requirements.txt",
          content: fixture("requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(4) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "dev-requirements.txt",
              groups: ["dev-dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with requirements/dev.txt" do
      let(:file) { [requirements] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements/dev.txt",
          content: fixture("requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(4) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements/dev.txt",
              groups: ["dev-dependencies"],
              source: nil
            }]
          )
        end
      end
    end

    context "with reference to its setup.py" do
      let(:files) { [requirements, setup_file] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("requirements", "with_setup_path.txt")
        )
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("setup_files", "setup.py")
        )
      end

      # setup.py dependencies get imported
      its(:length) { is_expected.to eq(15) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("requests")
          expect(dependency.version).to eq("2.1.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.1.0",
              file: "requirements.txt",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "==2.12.*",
              file: "setup.py",
              groups: ["install_requires"],
              source: nil
            }]
          )
        end
      end

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("flask")
          expect(dependency.version).to eq("0.12.2")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==0.12.2",
              file: "setup.py",
              groups: ["extras_require:API"],
              source: nil
            }]
          )
        end
      end

      context "in a nested requirements file" do
        let(:files) { [requirements, child_requirements, setup_file] }
        let(:requirements) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: fixture("requirements", "cascading_nested.txt")
          )
        end
        let(:child_requirements) do
          Dependabot::DependencyFile.new(
            name: "nested/more_requirements.txt",
            content: fixture("requirements", "with_setup_path.txt")
          )
        end
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "nested/setup.py",
            content: fixture("setup_files", "small_needs_sanitizing.py")
          )
        end

        # Note that the path dependency *isn't* parsed (because it's a manifest
        # for a path dependency, not for *this* project)
        its(:length) { is_expected.to eq(2) }
      end

      context "with a parse_requirements statement" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("setup_files", "with_parse_reqs.py")
          )
        end

        its(:length) { is_expected.to eq(5) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to eq("2.1.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==2.1.0",
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "with a file that must be executed as main" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("setup_files", "requires_main.py")
          )
        end

        its(:length) { is_expected.to eq(6) }

        describe "the last dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("flask")
            expect(dependency.version).to eq("0.12.2")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==0.12.2",
                file: "setup.py",
                groups: ["extras_require:API"],
                source: nil
              }]
            )
          end
        end
      end

      context "with a setup.cfg" do
        let(:files) { [requirements, setup_file, setup_cfg] }
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("setup_files", "with_pbr.py")
          )
        end
        let(:setup_cfg) do
          Dependabot::DependencyFile.new(
            name: "setup.cfg",
            content: fixture("setup_files", "setup.cfg")
          )
        end

        its(:length) { is_expected.to eq(3) }

        describe "the last dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("raven")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "setup.py",
                groups: ["install_requires"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with child requirement files" do
      let(:files) { [requirements, child_requirements] }
      let(:requirements_fixture_name) { "cascading.txt" }
      let(:child_requirements) do
        Dependabot::DependencyFile.new(
          name: "more_requirements.txt",
          content: fixture("requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(5) }

      it "has the right details" do
        expect(dependencies).to match_array(
          [
            Dependabot::Dependency.new(
              name: "requests",
              version: "2.4.1",
              requirements: [{
                requirement: "==2.4.1",
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "pip"
            ),
            Dependabot::Dependency.new(
              name: "aiocache[redis]",
              version: "0.10.0",
              requirements: [{
                requirement: "==0.10.0",
                file: "more_requirements.txt",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "pip"
            ),
            Dependabot::Dependency.new(
              name: "luigi",
              version: "2.2.0",
              requirements: [{
                requirement: "==2.2.0",
                file: "more_requirements.txt",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "pip"
            ),
            Dependabot::Dependency.new(
              name: "psycopg2",
              version: "2.6.1",
              requirements: [{
                requirement: "==2.6.1",
                file: "more_requirements.txt",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "pip"
            ),
            Dependabot::Dependency.new(
              name: "pytest",
              version: "3.4.0",
              requirements: [{
                requirement: "==3.4.0",
                file: "more_requirements.txt",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "pip"
            )
          ]
        )
      end
    end

    context "with a pip-compile file" do
      let(:files) { [manifest_file, generated_file] }
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.in",
          content: fixture("pip_compile_files", manifest_fixture_name)
        )
      end
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.txt",
          content: fixture("requirements", generated_fixture_name)
        )
      end
      let(:manifest_fixture_name) { "unpinned.in" }
      let(:generated_fixture_name) { "pip_compile_unpinned.txt" }

      its(:length) { is_expected.to eq(13) }

      describe "top level dependencies" do
        subject(:dependencies) { parser.parse.select(&:top_level?) }
        its(:length) { is_expected.to eq(5) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("attrs")
            expect(dependency.version).to eq("17.3.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "requirements/test.in",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        context "with filenames that can't be figured out" do
          let(:generated_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("requirements", generated_fixture_name)
            )
          end

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("apipkg")
              expect(dependency.version).to eq("1.4")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "==1.4",
                  file: "requirements.txt",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "the second dependency" do
            subject(:dependency) { dependencies[1] }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("attrs")
              expect(dependency.version).to eq("17.3.0")
              expect(dependency.requirements).to match_array(
                [{
                  requirement: nil,
                  file: "requirements/test.in",
                  groups: ["dependencies"],
                  source: nil
                }, {
                  requirement: "==17.3.0",
                  file: "requirements.txt",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a version bound" do
          let(:manifest_fixture_name) { "bounded.in" }
          let(:generated_fixture_name) { "pip_compile_bounded.txt" }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("attrs")
              expect(dependency.version).to eq("17.3.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "<=17.4.0",
                  file: "requirements/test.in",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end

      context "with a mismatching name" do
        let(:generated_file) do
          Dependabot::DependencyFile.new(
            name: "requirements/test-funky.txt",
            content: fixture("requirements", generated_fixture_name)
          )
        end
        let(:generated_fixture_name) { "pip_compile_unpinned_renamed.txt" }

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }
          its(:length) { is_expected.to eq(5) }
        end
      end
    end

    context "with a setup.py" do
      let(:files) { [setup_file] }
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("setup_files", "setup.py")
        )
      end

      its(:length) { is_expected.to eq(15) }

      describe "an install_requires dependencies" do
        subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("boto3")
          expect(dependency.version).to eq("1.3.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==1.3.1",
              file: "setup.py",
              groups: ["install_requires"],
              source: nil
            }]
          )
        end
      end

      context "with markers" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("setup_files", "markers.py")
          )
        end

        describe "a dependency with markers" do
          subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("boto3")
            expect(dependency.version).to eq("1.3.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==1.3.1",
                file: "setup.py",
                groups: ["install_requires"],
                source: nil
              }]
            )
          end
        end
      end

      context "with extras" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("setup_files", "extras.py")
          )
        end

        describe "a dependency with extras" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "requests[security]" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests[security]")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "==2.12.*",
                file: "setup.py",
                groups: ["install_requires"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with a setup.cfg" do
      let(:files) { [setup_cfg_file] }
      let(:setup_cfg_file) do
        Dependabot::DependencyFile.new(
          name: "setup.cfg",
          content: fixture("setup_files", "setup_with_requires.cfg")
        )
      end

      its(:length) { is_expected.to eq(15) }

      describe "an install_requires dependencies" do
        subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("boto3")
          expect(dependency.version).to eq("1.3.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==1.3.1",
              file: "setup.cfg",
              groups: ["install_requires"],
              source: nil
            }]
          )
        end
      end

      context "with markers" do
        let(:setup_cfg_file) do
          Dependabot::DependencyFile.new(
            name: "setup.cfg",
            content: fixture("setup_files", "markers.cfg")
          )
        end

        describe "a dependency with markers" do
          subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("boto3")
            expect(dependency.version).to eq("1.3.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==1.3.1",
                file: "setup.cfg",
                groups: ["install_requires"],
                source: nil
              }]
            )
          end
        end
      end

      context "with extras" do
        let(:setup_cfg_file) do
          Dependabot::DependencyFile.new(
            name: "setup.cfg",
            content: fixture("setup_files", "extras.cfg")
          )
        end

        describe "a dependency with extras" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "requests[security]" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests[security]")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "==2.12.*",
                file: "setup.cfg",
                groups: ["install_requires"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with a Pipfile and Pipfile.lock" do
      let(:files) { [pipfile, lockfile] }
      let(:pipfile) do
        Dependabot::DependencyFile.new(name: "Pipfile", content: pipfile_body)
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: lockfile_body
        )
      end

      let(:pipfile_body) { fixture("pipfiles", pipfile_fixture_name) }
      let(:lockfile_body) do
        fixture("lockfiles", lockfile_fixture_name)
      end
      let(:pipfile_fixture_name) { "version_not_specified" }
      let(:lockfile_fixture_name) { "version_not_specified.lock" }

      its(:length) { is_expected.to eq(7) }

      describe "top level dependencies" do
        subject(:dependencies) { parser.parse.select(&:top_level?) }
        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end

      context "that imports a path dependency" do
        let(:files) { [pipfile, lockfile, setup_file] }
        let(:pipfile_fixture_name) { "path_dependency_not_self" }
        let(:lockfile_fixture_name) { "path_dependency_not_self.lock" }
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "mydep/setup.py",
            content: fixture("setup_files", "small.py"),
            support_file: true
          )
        end

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }
          its(:length) { is_expected.to eq(2) }

          it "excludes the path dependency" do
            expect(dependencies.map(&:name)).to match_array(%w(requests pytest))
          end
        end
      end
    end

    context "with a Pipfile but no Pipfile.lock" do
      let(:files) { [pipfile] }
      let(:pipfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile",
          content: fixture("pipfiles", "version_not_specified")
        )
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("requests")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: "*",
              file: "Pipfile",
              groups: ["default"],
              source: nil
            }]
          )
        end
      end

      context "and a requirements.txt" do
        let(:files) { [pipfile, requirements] }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: fixture("pipfiles", "version_not_specified")
          )
        end

        its(:length) { is_expected.to eq(5) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "*",
                file: "Pipfile",
                groups: ["default"],
                source: nil
              }]
            )
          end
        end

        describe "the third dependency" do
          subject(:dependency) { dependencies[2] }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("psycopg2")
            expect(dependency.version).to eq("2.6.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==2.6.1",
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with a pyproject.toml and pyproject.lock" do
      let(:files) { [pyproject, pyproject_lock] }
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "pyproject.toml")
        )
      end
      let(:pyproject_lock) do
        Dependabot::DependencyFile.new(
          name: "pyproject.lock",
          content: fixture("pyproject_locks", "pyproject.lock")
        )
      end

      its(:length) { is_expected.to eq(36) }

      describe "top level dependencies" do
        subject(:dependencies) { parser.parse.select(&:top_level?) }
        its(:length) { is_expected.to eq(15) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("geopy")
            expect(dependency.version).to eq("1.14.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "^1.13",
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "and a requirements.txt" do
        let(:files) { [pyproject, requirements] }
        let(:pyproject) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "version_not_specified.toml")
          )
        end

        its(:length) { is_expected.to eq(5) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            # requests is only in version_not_specified.toml
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "*",
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        describe "the second dependency" do
          subject(:dependency) { dependencies[1] }

          it "has the right details" do
            # pytest is in both files, it picks version to be the lowest
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("pytest")
            expect(dependency.version).to eq("3.4.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "*",
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "==3.4.0",
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        describe "the third dependency" do
          subject(:dependency) { dependencies[2] }

          it "has the right details" do
            # psycopg2 only exists in version_specified.txt
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("psycopg2")
            expect(dependency.version).to eq("2.6.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "==2.6.1",
                file: "requirements.txt",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with reject_external_code" do
      let(:reject_external_code) { true }

      it "raises UnexpectedExternalCode" do
        expect { dependencies }.to raise_error(Dependabot::UnexpectedExternalCode)
      end
    end

    context "with multiple requirements" do
      let(:files) { project_dependency_files("poetry/multiple_requirements") }

      it "returns the dependencies with multiple requirements" do
        expect { dependencies }.not_to raise_error
        expect(dependencies.map(&:name)).to contain_exactly("numpy", "scipy")
      end
    end
  end
end
