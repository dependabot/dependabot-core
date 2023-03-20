# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/file_updater/manifest_updater"

RSpec.describe Dependabot::Composer::FileUpdater::ManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest: manifest,
      dependencies: [dependency]
    )
  end

  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: fixture("projects", project_name, "composer.json")
    )
  end
  let(:project_name) { "exact_version" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.22.1",
      requirements: [{
        file: "composer.json",
        requirement: "1.22.1",
        groups: [],
        source: nil
      }],
      previous_version: "1.0.1",
      previous_requirements: [{
        file: "composer.json",
        requirement: "1.0.1",
        groups: [],
        source: nil
      }],
      package_manager: "composer"
    )
  end

  describe "#updated_manifest_content" do
    subject(:updated_manifest_content) { updater.updated_manifest_content }

    it { is_expected.to include "\"monolog/monolog\" : \"1.22.1\"" }
    it { is_expected.to include "\"symfony/polyfill-mbstring\": \"1.0.1\"" }

    context "when the minor version is specified" do
      let(:project_name) { "minor_version" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.22.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.22.*",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it { is_expected.to include "\"monolog/monolog\": \"1.22.*\"" }
    end

    context "when a pre-release version is specified" do
      let(:project_name) { "prerelease_version" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.22.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.22.1",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.0-RC1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.0-RC1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it { is_expected.to include "\"monolog/monolog\": \"1.22.1\"" }
    end

    context "with a git source using no-api" do
      let(:project_name) { "git_source_no_api" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.6.0",
          requirements: [{
            file: "composer.json",
            requirement: "1.6.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it { is_expected.to include("no-api") }
    end

    context "when the dependency is a development dependency" do
      let(:project_name) { "development_dependencies" }

      it { is_expected.to include "\"monolog/monolog\": \"1.22.1\"" }
    end

    context "when the dependency is both development and runtime" do
      let(:project_name) { "dev_and_runtime_dep" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.22.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.22.1",
            groups: ["development"],
            source: nil
          }, {
            file: "composer.json",
            requirement: "^1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: ["development"],
            source: nil
          }, {
            file: "composer.json",
            requirement: "^1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it { is_expected.to include "\"monolog/monolog\": \"1.22.1\"" }
    end

    context "with non-standard whitespace" do
      let(:project_name) { "non_standard_whitespace" }

      it "keeps the non-standard whitespace" do
        expect(updated_manifest_content).
          to include %(\n    "monolog/monolog": "1.22.1",)
      end
    end
  end
end
