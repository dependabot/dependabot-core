# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip/pipfile_preparer"

RSpec.describe Dependabot::FileUpdaters::Python::Pip::PipfilePreparer do
  let(:preparer) { described_class.new(pipfile_content: pipfile_content) }

  let(:pipfile_content) do
    fixture("python", "pipfiles", pipfile_fixture_name)
  end
  let(:pipfile_fixture_name) { "version_not_specified" }

  describe "#freeze_top_level_dependencies_except" do
    subject(:updated_content) do
      preparer.freeze_top_level_dependencies_except(dependencies, lockfile)
    end

    let(:dependencies) do
      [
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
      ]
    end
    let(:dependency_name) { "requests" }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "Pipfile.lock",
        content: fixture("python", "lockfiles", lockfile_fixture_name)
      )
    end
    let(:pipfile_fixture_name) { "version_not_specified" }
    let(:lockfile_fixture_name) { "version_not_specified.lock" }

    context "with a dev dependency that needs locking" do
      let(:dependency_name) { "requests" }
      it "locks the dependency" do
        expect(updated_content).to include('pytest = "==3.2.3"')
      end
    end

    context "with a production dependency that needs locking" do
      let(:dependency_name) { "pytest" }
      it "locks the dependency" do
        expect(updated_content).to include('requests = "==2.18.0"')
      end

      context "and appears as a string in the lockfile" do
        # Requests has been edited to use a string, rather than hash of details
        # in its lockfile
        let(:lockfile_fixture_name) { "edited.lock" }

        it "locks the dependency" do
          expect(updated_content).to include('requests = "==2.18.0"')
        end
      end

      context "and appears as an array in the lockfile (i.e., unusable)" do
        let(:lockfile_fixture_name) { "edited_array.lock" }

        it "does not lock the dependency" do
          expect(updated_content).to include('requests = "*"')
        end
      end

      context "that is a git dependency" do
        let(:pipfile_fixture_name) { "git_source_no_ref" }
        let(:lockfile_fixture_name) { "git_source_no_ref.lock" }

        it "locks the dependency" do
          expect(updated_content).to include(
            "[packages.pythonfinder]\n"\
            "git = \"https://github.com/sarugaku/pythonfinder.git\"\n"\
            "ref = \"9ee85b83290850f99dec2c0ec58a084305047347\"\n"
          )
        end

        context "but already has a reference" do
          let(:pipfile_fixture_name) { "git_source" }
          let(:lockfile_fixture_name) { "git_source.lock" }

          it "leaves the dependency alone" do
            expect(updated_content).to include(
              "[packages.django]\n"\
              "git = \"https://github.com/django/django.git\"\n"\
              "ref = \"1.11.4\"\n"
            )
          end
        end
      end
    end
  end
end
