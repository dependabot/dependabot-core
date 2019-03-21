# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pipfile_manifest_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::PipfileManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest: manifest,
      dependencies: [dependency]
    )
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfiles", pipfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "version_not_specified" }
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

  describe "#updated_manifest_content" do
    subject(:updated_manifest_content) { updater.updated_manifest_content }

    context "when the Pipfile hasn't changed" do
      let(:pipfile_fixture_name) { "version_not_specified" }
      it { is_expected.to eq(manifest.content) }
    end

    context "with single quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python-decouple",
          version: "3.2",
          previous_version: "3.1",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.2",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }],
          previous_requirements: [{
            requirement: "==3.1",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        )
      end

      it { is_expected.to include(%q('python_decouple' = "==3.2")) }
    end

    context "with double quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
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

      it { is_expected.to include('"requests" = "==2.18.4"') }
    end

    context "without quotes" do
      let(:pipfile_fixture_name) { "with_quotes" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pytest",
          version: "3.3.1",
          previous_version: "3.2.3",
          package_manager: "pip",
          requirements: [{
            requirement: "==3.3.1",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }],
          previous_requirements: [{
            requirement: "==3.2.3",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }]
        )
      end

      it { is_expected.to include(%(\npytest = "==3.3.1"\n)) }
      it { is_expected.to include(%(\npytest-extension = "==3.2.3"\n)) }
      it { is_expected.to include(%(\nextension-pytest = "==3.2.3"\n)) }
    end

    context "with a version in a hash" do
      let(:pipfile_fixture_name) { "version_hash" }
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

      it { is_expected.to include('requests = { version = "==2.18.4" }') }
    end

    context "with a declaration table" do
      let(:pipfile_fixture_name) { "version_table" }
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

      it { is_expected.to include(%(kages.requests]\n\nversion = "==2.18.4")) }
    end

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

      it { is_expected.to include('Requests = "==2.18.4"') }
    end
  end
end
