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
    Dependabot::DependencyFile.new(content: pipfile_body, name: "Pipfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Pipfile.lock")
  end
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
    subject(:updated_dependency_files) { updater.updated_dependency_files }

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

      it "updates the lockfiles successfully" do
        expect(updated_dependency_files.last.content).
          to include('"version": "==2.18.4"')
      end
    end
  end

  describe "#updated_pipfile_content" do
    subject(:updated_pipfile_content) { updater.send(:updated_pipfile_content) }

    let(:pipfile_body) do
      fixture("python", "pipfiles", "version_not_specified")
    end
    let(:lockfile_body) do
      fixture("python", "lockfiles", "version_not_specified.lock")
    end

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
