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
      dependency_files: [composer_json, lockfile],
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
            previous_version: "1.1.13beta.2",
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "1.1.13beta.2",
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

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end

      it { is_expected.to include "\"prefer-stable\":false" }

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

      context "with a git URL" do
        let(:composer_body) do
          fixture("php", "composer_files", "git_source_git_url")
        end
        let(:lockfile_body) do
          fixture("php", "lockfiles", "git_source_git_url")
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
          expect(updated_lockfile_content).
            to include("git@github.com:dependabot/monolog.git")
          expect(updated_lockfile_content).
            to include("https://github.com/symfony/polyfill-mbstring.git")
        end
      end
    end
  end
end
