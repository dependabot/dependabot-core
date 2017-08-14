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
      requirement: "1.0.*",
      package_manager: "composer",
      groups: []
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
    it { is_expected.to be >= Gem::Version.new("1.22.0") }
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "doctrine/dbal",
          version: "2.1.5",
          requirement: "1.0.*",
          package_manager: "composer",
          groups: []
        )
      end

      let(:composer_file_content) do
        fixture("php", "composer_files", "version_conflict")
      end
      let(:lockfile_content) do
        fixture("php", "lockfiles", "version_conflict")
      end

      it { is_expected.to be < Gem::Version.new("3.0.0") }
      it { is_expected.to be > Gem::Version.new("2.0.0") }
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
            requirement: "1.0.*",
            package_manager: "composer",
            groups: []
          )
        end

        it { is_expected.to be >= Gem::Version.new("1.3.0") }
      end
    end
  end

  describe "#updated_requirement" do
    subject { checker.updated_requirement }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "monolog/monolog",
        version: "1.0.1",
        requirement: original_requirement,
        package_manager: "composer",
        groups: []
      )
    end

    let(:original_requirement) { "1.0.*" }
    let(:latest_resolvable_version) { nil }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(latest_resolvable_version)
    end

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      it { is_expected.to be_nil }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { "1.5.0" }

      context "and a full version was previously specified" do
        let(:original_requirement) { "1.4.0" }
        it { is_expected.to eq("1.5.0") }
      end

      context "and a pre-release was previously specified" do
        let(:original_requirement) { "1.5.0beta" }
        it { is_expected.to eq("1.5.0") }
      end

      context "and a minor version was previously specified" do
        let(:original_requirement) { "1.4.*" }
        it { is_expected.to eq("1.5.*") }
      end
    end
  end
end
