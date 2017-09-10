# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/php/composer"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Php::Composer do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [composer_file, lockfile],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.0.1",
      requirements: [
        { file: "composer.json", requirement: "1.0.*", groups: [] }
      ],
      package_manager: "composer"
    )
  end

  let(:composer_file) do
    Dependabot::DependencyFile.new(
      content: composer_file_content,
      name: "composer.json"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: lockfile_content,
      name: "composer.lock"
    )
  end
  let(:composer_file_content) do
    fixture("php", "composer_files", "exact_version")
  end
  let(:lockfile_content) { fixture("php", "lockfiles", "exact_version") }

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:packagist_url) { "https://packagist.org/p/monolog/monolog.json" }
    let(:packagist_response) { fixture("php", "packagist_response.json") }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "doctrine/dbal",
          version: "2.1.5",
          requirements: [
            { file: "composer.json", requirement: "1.0.*", groups: [] }
          ],
          package_manager: "composer"
        )
      end

      let(:composer_file_content) do
        fixture("php", "composer_files", "version_conflict")
      end
      let(:lockfile_content) do
        fixture("php", "lockfiles", "version_conflict")
      end

      it "is between 2.0.0 and 3.0.0" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.0")
      end
    end

    context "with a dependency with a git source" do
      let(:lockfile_content) { fixture("php", "lockfiles", "git_source") }
      let(:composer_file_content) do
        fixture("php", "composer_files", "git_source")
      end

      context "that is the gem we're checking" do
        it { is_expected.to be_nil }
      end

      context "that is not the gem we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "symfony/polyfill-mbstring",
            version: "1.0.1",
            requirements: [
              { file: "composer.json", requirement: "1.0.*", groups: [] }
            ],
            package_manager: "composer"
          )
        end

        it { is_expected.to be >= Gem::Version.new("1.3.0") }
      end
    end

    context "when an alternative source is specified" do
      let(:composer_file_content) do
        fixture("php", "composer_files", "alternative_source")
      end
      let(:lockfile_content) do
        fixture("php", "lockfiles", "alternative_source")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "wpackagist-plugin/acf-to-rest-api",
          version: "2.2.1",
          requirements: [
            { file: "composer.json", requirement: "*", groups: ["runtime"] }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("2.2.1") }
    end

    context "when an autoload is specified" do
      let(:composer_file_content) do
        fixture("php", "composer_files", "autoload")
      end
      let(:lockfile_content) do
        fixture("php", "lockfiles", "autoload")
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/support",
          version: "v5.2.7",
          requirements: [
            {
              file: "composer.json",
              requirement: "^5.2.0",
              groups: ["runtime"]
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("5.2.7") }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "monolog/monolog",
        version: "1.0.1",
        requirements: [
          { file: "composer.json", requirement: old_requirement, groups: [] }
        ],
        package_manager: "composer"
      )
    end

    let(:old_requirement) { "1.0.*" }
    let(:latest_resolvable_version) { nil }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(latest_resolvable_version)
    end

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(old_requirement) }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

      context "and a full version was previously specified" do
        let(:old_requirement) { "1.4.0" }
        its([:requirement]) { is_expected.to eq("1.5.0") }
      end

      context "and a pre-release was previously specified" do
        let(:old_requirement) { "1.5.0beta" }
        its([:requirement]) { is_expected.to eq("1.5.0") }
      end

      context "and a minor version was previously specified" do
        let(:old_requirement) { "1.4.*" }
        its([:requirement]) { is_expected.to eq("1.5.*") }
      end
    end
  end
end
