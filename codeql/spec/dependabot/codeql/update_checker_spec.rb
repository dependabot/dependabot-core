# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/package/release_cooldown_options"
require "dependabot/codeql/update_checker"
require "dependabot/codeql/registry_client"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Codeql::UpdateChecker do
  subject(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions,
      update_cooldown: update_cooldown
    )
  end

  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end
  let(:ignored_versions) { [] }
  let(:update_cooldown) { nil }
  let(:tags) { %w(0.9.0 0.9.1 0.9.5 0.10.0) }
  let(:registry_client) { instance_double(Dependabot::Codeql::RegistryClient) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "codeql/java-all",
      version: "0.9.1",
      requirements: [{
        requirement: "^0.9.1",
        groups: [],
        file: "qlpack.yml",
        source: { type: "codeql_pack_registry" }
      }],
      package_manager: "codeql"
    )
  end

  before do
    allow(Dependabot::Codeql::RegistryClient).to receive(:new).and_return(registry_client)
    allow(registry_client).to receive(:tags).with("codeql/java-all").and_return(tags)
    allow(registry_client).to receive(:release_dates).with("codeql/java-all").and_return({})
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    it "returns the highest published version" do
      expect(checker.latest_version).to eq(Dependabot::Codeql::Version.new("0.10.0"))
    end

    context "when versions are ignored" do
      let(:ignored_versions) { [">= 0.10.0"] }

      it "returns the highest non-ignored version" do
        expect(checker.latest_version).to eq(Dependabot::Codeql::Version.new("0.9.5"))
      end
    end

    context "with prerelease tags" do
      let(:tags) { %w(0.9.0 0.9.1 0.11.0-alpha) }

      it "ignores prereleases when the current version is stable" do
        expect(checker.latest_version).to eq(Dependabot::Codeql::Version.new("0.9.1"))
      end
    end
  end

  describe "#latest_resolvable_version" do
    it "matches latest_version" do
      expect(checker.latest_resolvable_version).to eq(Dependabot::Codeql::Version.new("0.10.0"))
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    it "returns the highest version still inside the current range" do
      expect(checker.latest_resolvable_version_with_no_unlock)
        .to eq(Dependabot::Codeql::Version.new("0.9.5"))
    end
  end

  describe "#up_to_date?" do
    context "when a newer version exists" do
      it { expect(checker).not_to be_up_to_date }
    end

    context "when already on the latest version" do
      let(:tags) { %w(0.9.0 0.9.1) }

      it { expect(checker).to be_up_to_date }
    end
  end

  describe "#updated_requirements" do
    context "when the latest version is outside the current range" do
      it "bumps the caret range to the new version" do
        expect(checker.updated_requirements.first[:requirement]).to eq("^0.10.0")
      end
    end

    context "when the latest version stays within the current range" do
      let(:tags) { %w(0.9.0 0.9.1 0.9.5) }

      it "leaves the requirement unchanged" do
        expect(checker.updated_requirements.first[:requirement]).to eq("^0.9.1")
      end
    end

    context "when the requirement is an exact pin" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "codeql/java-all",
          version: "0.9.1",
          requirements: [{
            requirement: "0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          package_manager: "codeql"
        )
      end

      it "bumps the pin to the new version without introducing a caret range" do
        expect(checker.updated_requirements.first[:requirement]).to eq("0.10.0")
      end
    end

    context "when the requirement uses a comparison operator" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "codeql/java-all",
          version: "0.9.1",
          requirements: [{
            requirement: "~> 0.9.1",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          package_manager: "codeql"
        )
      end

      it "preserves the operator when bumping to the new version" do
        expect(checker.updated_requirements.first[:requirement]).to eq("~> 0.10.0")
      end
    end

    context "when the requirement is a wildcard" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "codeql/java-all",
          version: "0.9.1",
          requirements: [{
            requirement: "*",
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }],
          package_manager: "codeql"
        )
      end

      it "leaves the wildcard unchanged" do
        expect(checker.updated_requirements.first[:requirement]).to eq("*")
      end
    end
  end

  describe "cooldown filtering" do
    let(:update_cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7, include: ["codeql/java-all"])
    end

    context "when the newest version is still within its cooldown window" do
      before do
        allow(registry_client).to receive(:release_dates).with("codeql/java-all").and_return(
          "0.10.0" => Time.now - (2 * 24 * 60 * 60),
          "0.9.5" => Time.now - (60 * 24 * 60 * 60)
        )
      end

      it "skips the cooling-down version and picks the next stable one" do
        expect(checker.latest_version).to eq(Dependabot::Codeql::Version.new("0.9.5"))
      end
    end

    context "when release dates are unavailable" do
      before do
        allow(registry_client).to receive(:release_dates).with("codeql/java-all").and_return({})
      end

      it "does not filter anything" do
        expect(checker.latest_version).to eq(Dependabot::Codeql::Version.new("0.10.0"))
      end
    end
  end
end
