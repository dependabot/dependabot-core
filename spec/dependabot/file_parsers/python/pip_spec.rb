# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/python/pip"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Python::Pip do
  it_behaves_like "a dependency file parser"

  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  let(:files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: requirements_body
    )
  end
  let(:requirements_body) do
    fixture("python", "requirements", requirements_fixture_name)
  end
  let(:requirements_fixture_name) { "version_specified.txt" }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

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
              groups: [],
              source: nil
            }]
          )
        end
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
              groups: [],
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
          expect(dependency.name).to eq("psycopg2")
          expect(dependency.version).to eq("2.6.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==2.6.1",
              file: "requirements.txt",
              groups: [],
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

    context "with invalid options" do
      let(:requirements_fixture_name) { "invalid_options.txt" }

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
            content: fixture("python", "constraints", "less_than.txt")
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("requests")
            expect(dependency.version).to be_nil
            expect(dependency.requirements.first[:requirement]).
              to eq("<2.0.0")
            expect(dependency.requirements.last[:requirement]).to be_nil
          end
        end
      end

      context "that are specific" do
        let(:constraints) do
          Dependabot::DependencyFile.new(
            name: "constraints.txt",
            content: fixture("python", "constraints", "specific.txt")
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
              [
                {
                  requirement: nil,
                  file: "requirements.txt",
                  groups: [],
                  source: nil
                },
                {
                  requirement: "==2.0.0",
                  file: "constraints.txt",
                  groups: [],
                  source: nil
                }
              ]
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
                [
                  {
                    requirement: "==2.0.0",
                    file: "constraints.txt",
                    groups: [],
                    source: nil
                  },
                  {
                    requirement: "==2.4.1",
                    file: "requirements.txt",
                    groups: [],
                    source: nil
                  }
                ]
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
          content: fixture("python", "requirements", "version_specified.txt")
        )
      end

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
              file: "requirements-dev.txt",
              groups: [],
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
          content: fixture("python", "requirements", "version_specified.txt")
        )
      end

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
              file: "dev-requirements.txt",
              groups: [],
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
          content: fixture("python", "requirements", "version_specified.txt")
        )
      end

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
              file: "requirements/dev.txt",
              groups: [],
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
          content: fixture("python", "requirements", "with_setup_path.txt")
        )
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("python", "setup_files", "setup.py")
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
            [
              {
                requirement: "==2.1.0",
                file: "requirements.txt",
                groups: [],
                source: nil
              },
              {
                requirement: "==2.12.*",
                file: "setup.py",
                groups: [],
                source: nil
              }
            ]
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
              groups: [],
              source: nil
            }]
          )
        end
      end

      context "with a parse_requirements statement" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "with_parse_reqs.py")
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
                groups: [],
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
          content: fixture("python", "requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(3) }

      it "has the right details" do
        expect(dependencies).to match_array(
          [
            Dependabot::Dependency.new(
              name: "requests",
              version: "2.4.1",
              requirements: [{
                requirement: "==2.4.1",
                file: "requirements.txt",
                groups: [],
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
                groups: [],
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
                groups: [],
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
          content: fixture("python", "pip_compile_files", manifest_fixture_name)
        )
      end
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.txt",
          content: fixture("python", "requirements", generated_fixture_name)
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
                groups: [],
                source: nil
              }]
            )
          end
        end

        context "with filenames that can't be figured out" do
          let(:generated_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("python", "requirements", generated_fixture_name)
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
                  groups: [],
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
                [
                  {
                    requirement: nil,
                    file: "requirements/test.in",
                    groups: [],
                    source: nil
                  },
                  {
                    requirement: "==17.3.0",
                    file: "requirements.txt",
                    groups: [],
                    source: nil
                  }
                ]
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
                  groups: [],
                  source: nil
                }]
              )
            end
          end
        end
      end
    end

    context "with a setup.py" do
      let(:files) { [setup_file] }
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("python", "setup_files", "setup.py")
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
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "a setup_requires dependencies" do
        subject(:dependency) { dependencies.find { |d| d.name == "numpy" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("numpy")
          expect(dependency.version).to eq("1.11.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==1.11.0",
              file: "setup.py",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "a tests_require dependencies" do
        subject(:dependency) { dependencies.find { |d| d.name == "responses" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("responses")
          expect(dependency.version).to eq("0.5.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==0.5.1",
              file: "setup.py",
              groups: [],
              source: nil
            }]
          )
        end
      end

      describe "an extras_require dependencies" do
        subject(:dependency) { dependencies.find { |d| d.name == "flask" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("flask")
          expect(dependency.version).to eq("0.12.2")
          expect(dependency.requirements).to eq(
            [{
              requirement: "==0.12.2",
              file: "setup.py",
              groups: [],
              source: nil
            }]
          )
        end
      end

      context "without a `tests_require` key" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "no_tests_require.py")
          )
        end

        its(:length) { is_expected.to eq(12) }
      end

      context "with a `print` statement" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "with_print.py")
          )
        end

        its(:length) { is_expected.to eq(14) }
      end

      context "with an illformed_requirement" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "illformed_req.py")
          )
        end

        it "raises a helpful error" do
          expect { parser.parse }.
            to raise_error do |error|
              expect(error.class).
                to eq(Dependabot::DependencyFileNotEvaluatable)
              expect(error.message).
                to eq('Illformed requirement ["==2.6.1raven==5.32.0"]')
            end
        end
      end

      context "with an `open` statement" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "with_open.py")
          )
        end

        its(:length) { is_expected.to eq(14) }
      end

      context "with the setup.py from requests" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "requests_setup.py")
          )
        end

        its(:length) { is_expected.to eq(13) }
      end

      context "with an import of a config file" do
        let(:setup_file) do
          Dependabot::DependencyFile.new(
            name: "setup.py",
            content: fixture("python", "setup_files", "imports_version.py")
          )
        end

        its(:length) { is_expected.to eq(14) }
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

      let(:pipfile_body) { fixture("python", "pipfiles", pipfile_fixture_name) }
      let(:lockfile_body) do
        fixture("python", "lockfiles", lockfile_fixture_name)
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
          it { is_expected.to be_production }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end

      describe "sub-dependencies" do
        subject(:dependencies) { parser.parse.reject(&:top_level?) }
        its(:length) { is_expected.to eq(5) }

        describe "the first dependency" do
          subject { dependencies.first }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("certifi") }
          its(:version) { is_expected.to eq("2017.11.5") }
          its(:requirements) { is_expected.to eq([]) }
        end
      end

      context "with a version specified" do
        let(:pipfile_fixture_name) { "exact_version" }
        let(:lockfile_fixture_name) { "exact_version.lock" }

        its(:length) { is_expected.to eq(11) }

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }

          its(:length) { is_expected.to eq(2) }

          describe "the last dependency" do
            subject { dependencies.last }
            let(:expected_requirements) do
              [{
                requirement: "==3.4.0",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }]
            end

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("pytest") }
            its(:version) { is_expected.to eq("3.4.0") }
            its(:requirements) { is_expected.to eq(expected_requirements) }
          end
        end

        context "using arbitrary equality" do
          let(:pipfile_fixture_name) { "arbitrary_equality" }
          let(:lockfile_fixture_name) { "arbitrary_equality.lock" }

          describe "top level dependencies" do
            subject(:dependencies) { parser.parse.select(&:top_level?) }

            describe "the last dependency" do
              subject { dependencies.last }
              let(:expected_requirements) do
                [{
                  requirement: "===3.4.0",
                  file: "Pipfile",
                  source: nil,
                  groups: ["develop"]
                }]
              end

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("pytest") }
              its(:version) { is_expected.to eq("3.4.0") }
              its(:requirements) { is_expected.to eq(expected_requirements) }
            end
          end
        end
      end

      context "with only dev dependencies" do
        let(:pipfile_fixture_name) { "only_dev" }
        let(:lockfile_fixture_name) { "only_dev.lock" }

        its(:length) { is_expected.to eq(5) }

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }

          its(:length) { is_expected.to eq(1) }

          describe "the last dependency" do
            subject { dependencies.first }
            let(:expected_requirements) do
              [{
                requirement: "*",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }]
            end

            it { is_expected.to be_a(Dependabot::Dependency) }
            it { is_expected.to_not be_production }
            its(:name) { is_expected.to eq("pytest") }
            its(:version) { is_expected.to eq("3.3.1") }
            its(:requirements) { is_expected.to eq(expected_requirements) }
          end
        end
      end

      context "with dependency names that need normalising" do
        let(:pipfile_fixture_name) { "hard_names" }
        let(:lockfile_fixture_name) { "hard_names.lock" }

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }

          its(:length) { is_expected.to eq(3) }

          describe "the first dependency" do
            subject { dependencies.first }
            let(:expected_requirements) do
              [{
                requirement: "==2.18.0",
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
      end

      context "with the version specified in a hash" do
        let(:pipfile_fixture_name) { "version_hash" }
        let(:lockfile_fixture_name) { "version_hash.lock" }

        describe "top level dependencies" do
          subject(:dependencies) { parser.parse.select(&:top_level?) }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject { dependencies.first }
            let(:expected_requirements) do
              [{
                requirement: "==2.18.0",
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
      end

      context "with no entry in the Pipfile.lock" do
        let(:pipfile_fixture_name) { "not_in_lockfile" }
        let(:lockfile_fixture_name) { "only_dev.lock" }

        it "excludes the missing dependency" do
          expect(dependencies.map(&:name)).to_not include("missing")
        end

        describe "the dependency" do
          subject { dependencies.find { |d| d.name == "pytest" } }
          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("pytest") }
          its(:version) { is_expected.to eq("3.3.1") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end

      context "with a git source" do
        let(:pipfile_fixture_name) { "git_source" }
        let(:lockfile_fixture_name) { "git_source.lock" }

        it "excludes the git dependency" do
          expect(dependencies.map(&:name)).to_not include("django")
        end

        describe "the dependency" do
          subject { dependencies.find { |d| d.name == "requests" } }
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
          its(:version) { is_expected.to eq("2.18.4") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with a Pipfile but no Pipfile.lock" do
      let(:files) { [pipfile, requirements] }
      let(:pipfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile",
          content: fixture("python", "pipfiles", "version_not_specified")
        )
      end

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
              groups: [],
              source: nil
            }]
          )
        end
      end
    end
  end
end
