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
      dependency: dependency,
      github_access_token: "token"
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
        { file: "composer.json", requirement: "1.22.*", groups: [] }
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

      it do
        is_expected.to include "\"monolog/monolog\":\"1.22.1\""
      end

      it { is_expected.to include "\"symfony/polyfill-mbstring\":\"1.0.1\"" }

      context "when the minor version is specified" do
        let(:composer_body) do
          fixture("php", "composer_files", "minor_version")
        end

        it { is_expected.to include "\"monolog/monolog\":\"1.22.*\"" }
      end

      context "when a pre-release version is specified" do
        let(:composer_body) do
          fixture("php", "composer_files", "prerelease_version")
        end

        it { is_expected.to include "\"monolog/monolog\":\"1.22.1\"" }
      end

      context "when the dependency is a development dependency" do
        let(:composer_body) do
          fixture("php", "composer_files", "development_dependencies")
        end

        pending { is_expected.to include "\"monolog/monolog\":\"1.22.1\"" }
      end
    end

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        raw = updated_files.find { |f| f.name == "composer.lock" }.content
        JSON.parse(raw).to_json
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).
          to include("\"version\":\"1.22.1\"")
      end
    end
  end
end
