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
      dependency: dependency,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:dependency_files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      content: requirements_body,
      name: "requirements.txt"
    )
  end
  let(:requirements_body) do
    fixture("python", "requirements", "version_specified.txt")
  end
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
        let(:requirements_body) do
          fixture("python", "requirements", "minor_version_specified.txt")
        end

        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      end

      context "when there is a comment" do
        let(:requirements_body) do
          fixture("python", "requirements", "comments.txt")
        end
        its(:content) { is_expected.to include "psycopg2==2.8.1  # Comment!\n" }
      end

      context "when there are unused lines" do
        let(:requirements_body) do
          fixture("python", "requirements", "invalid_lines.txt")
        end
        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
        its(:content) { is_expected.to include "# This is just a comment" }
      end

      context "when the dependency is in a child requirement file" do
        let(:dependency_files) { [requirements, more_requirements] }

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

        let(:requirements_body) do
          fixture("python", "requirements", "cascading.txt")
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

      let(:requirements_body) do
        fixture("python", "requirements", "specific_with_constraints.txt")
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
  end
end
