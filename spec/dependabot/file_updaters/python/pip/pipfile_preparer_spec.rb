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
    end
  end

  describe "#replace_ssh_git_urls" do
    subject(:updated_content) { preparer.replace_ssh_git_urls }

    context "with a git source that already uses https" do
      let(:pipfile_fixture_name) { "git_source" }

      it "keeps the existing https URL" do
        expect(updated_content).
          to include('git = "https://github.com/django/django.git"')
      end
    end

    context "with a git source that uses ssh" do
      let(:pipfile_fixture_name) { "git_source_ssh" }

      it "switches to https" do
        expect(updated_content).
          to include('git = "https://github.com/requests/requests"')
      end
    end

    context "with a git source that uses a git URL" do
      let(:pipfile_fixture_name) { "git_source_git_url" }

      it "switches to https" do
        expect(updated_content).
          to include('git = "https://github.com/requests/requests"')
      end
    end
  end
end
