# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/php/composer"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Php::Composer do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Dependabot::DependencyFile.new(
      content: composer_body,
      name: "composer.json"
    )
  end
  let(:composer_body) { fixture("php", "composer_files", "exact_version") }

  let(:lockfile_body) { fixture("php", "lockfiles", "exact_version") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: lockfile_body
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.22.1",
      requirements: [
        {
          file: "composer.json",
          requirement: "1.22.1",
          groups: [],
          source: nil
        }
      ],
      previous_version: "1.0.1",
      previous_requirements: [
        {
          file: "composer.json",
          requirement: "1.0.1",
          groups: [],
          source: nil
        }
      ],
      package_manager: "composer"
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

    it { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(2) }

    describe "the updated composer_file" do
      subject(:updated_composer_file_content) do
        # Parse and marshal, so we know the formatting
        raw = updated_files.find { |f| f.name == "composer.json" }.content
        JSON.parse(raw).to_json
      end

      it { is_expected.to include "\"monolog/monolog\":\"1.22.1\"" }

      it { is_expected.to include "\"symfony/polyfill-mbstring\":\"1.0.1\"" }

      context "when the minor version is specified" do
        let(:composer_body) do
          fixture("php", "composer_files", "minor_version")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "monolog/monolog",
            version: "1.22.1",
            requirements: [
              {
                file: "composer.json",
                requirement: "1.22.*",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.0.1",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "1.0.*",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it { is_expected.to include "\"monolog/monolog\":\"1.22.*\"" }
      end

      context "when a pre-release version is specified" do
        let(:composer_body) do
          fixture("php", "composer_files", "prerelease_version")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "prerelease_version")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "monolog/monolog",
            version: "1.22.1",
            requirements: [
              {
                file: "composer.json",
                requirement: "1.22.1",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.0.0-RC1",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "1.0.0-RC1",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it { is_expected.to include "\"monolog/monolog\":\"1.22.1\"" }
      end

      context "when the dependency is a development dependency" do
        let(:composer_body) do
          fixture("php", "composer_files", "development_dependencies")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "development_dependencies")
        end

        it { is_expected.to include "\"monolog/monolog\":\"1.22.1\"" }
      end

      context "with non-standard whitespace" do
        let(:composer_body) do
          fixture("php", "composer_files", "non_standard_whitespace")
        end

        it "keeps the non-standard whitespace" do
          file = updated_files.find { |f| f.name == "composer.json" }
          expect(file.content).to include %(\n    "monolog/monolog": "1.22.1",)
        end
      end
    end

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        raw = updated_files.find { |f| f.name == "composer.lock" }.content
        JSON.parse(raw).to_json
      end

      context "without a lockfile" do
        let(:files) { [composer_json] }
        specify { expect(updated_files.map(&:name)).to eq(["composer.json"]) }
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end

      it { is_expected.to include "\"prefer-stable\":false" }

      context "that requires an environment variable" do
        let(:composer_body) do
          fixture("php", "composer_files", "env_variable")
        end

        context "that hasn't been provided" do
          it "raises a MissingEnvironmentVariable error" do
            expect { updated_files }.to raise_error do |error|
              expect(error).to be_a(Dependabot::MissingEnvironmentVariable)
              expect(error.environment_variable).to eq("ACF_PRO_KEY")
            end
          end
        end

        context "that has been provided" do
          let(:updater) do
            described_class.new(
              dependency_files: files,
              dependencies: [dependency],
              credentials: [
                {
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                },
                {
                  "env-key" => "ACF_PRO_KEY",
                  "env-value" => "example_key"
                }
              ]
            )
          end

          it "runs just fine (we get a 400 here because our key is wrong)" do
            expect { updated_files }.to raise_error do |error|
              expect(error).
                to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
              expect(error.message).to include("400 Bad Request")
            end
          end
        end
      end

      context "when the new version is covered by the old requirements" do
        let(:composer_body) do
          fixture("php", "composer_files", "minor_version")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "covered_version")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "monolog/monolog",
            version: "1.0.2",
            requirements: [
              {
                file: "composer.json",
                requirement: "1.0.*",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.0.0",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "1.0.*",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          updated_dep = JSON.parse(updated_lockfile_content).
                        fetch("packages").
                        find { |p| p["name"] == "monolog/monolog" }

          expect(updated_dep.fetch("version")).to eq("1.0.2")
        end
      end

      context "when the dependency is a development dependency" do
        let(:composer_body) do
          fixture("php", "composer_files", "development_dependencies")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "development_dependencies")
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
        end
      end

      context "when another dependency has git source with a bad reference" do
        let(:lockfile_body) do
          fixture("php", "lockfiles", "git_source_bad_ref")
        end
        let(:composer_body) do
          fixture("php", "composer_files", "git_source_bad_ref")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "symfony/polyfill-mbstring",
            version: "1.6.0",
            requirements: [
              {
                file: "composer.json",
                requirement: "1.6.0",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.0.1",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "1.0.1",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it "raises a helpful errors" do
          expect { updated_files }.to raise_error do |error|
            expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
            expect(error.dependency).to eq("monolog/monolog")
          end
        end
      end

      context "regression spec for media-organizer" do
        let(:composer_body) do
          fixture("php", "composer_files", "media_organizer")
        end
        let(:lockfile_body) { fixture("php", "lockfiles", "media_organizer") }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "monolog/monolog",
            version: "1.23.0",
            requirements: [
              {
                file: "composer.json",
                requirement: "~1.0",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.20.0",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "~1.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          updated_dep = JSON.parse(updated_lockfile_content).
                        fetch("packages-dev").
                        find { |p| p["name"] == "monolog/monolog" }

          expect(Gem::Version.new(updated_dep.fetch("version"))).
            to be >= Gem::Version.new("1.23.0")
        end
      end

      context "when an old version of PHP is specified" do
        let(:composer_body) do
          fixture("php", "composer_files", "old_php_specified")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "old_php_specified")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "illuminate/support",
            version: "v5.4.36",
            requirements: [
              {
                file: "composer.json",
                requirement: "^5.4.36",
                groups: ["runtime"],
                source: nil
              }
            ],
            previous_version: "v5.2.1",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "^5.2.0",
                groups: ["runtime"],
                source: nil
              }
            ],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"v5.4.36\"")
        end
      end
    end
  end
end
