# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.3.0",
      requirements: [
        { file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }
      ],
      package_manager: "hex"
    )
  end

  let(:files) { [mixfile, lockfile] }

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: mixfile_body,
      name: "mix.exs"
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: lockfile_body,
      name: "mix.lock"
    )
  end

  let(:mixfile_body) do
    fixture("elixir", "mixfiles", "minor_version")
  end

  let(:lockfile_body) do
    fixture("elixir", "lockfiles", "minor_version")
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:hex_url) { "https://hex.pm/api/packages/plug" }
    let(:hex_response) do
      fixture("elixir", "registry_api", "plug_response.json")
    end

    before do
      stub_request(:get, hex_url).
        to_return(status: 200, body: hex_response)
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.3.5"))
    end

    it { is_expected.to eq(Gem::Version.new("1.4.3")) }

    context "when packagist 404s" do
      before { stub_request(:get, hex_url).to_return(status: 404) }

      it { is_expected.to eq(Gem::Version.new("1.3.5")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it { is_expected.to be Gem::Version.new("1.3.5") }

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "doctrine/dbal",
          version: "2.1.5",
          requirements: [
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
            {
              file: "composer.json",
              requirement: "*",
              groups: ["runtime"],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("2.2.1") }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "monolog/monolog",
        version: "1.0.1",
        requirements: [
          {
            file: "composer.json",
            requirement: old_requirement,
            groups: [],
            source: nil
          }
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
