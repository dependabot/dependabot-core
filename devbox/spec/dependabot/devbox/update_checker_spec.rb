# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers"
require "dependabot/devbox/update_checker"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Devbox::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      security_advisories: [],
      ignored_versions: ignored_versions,
      update_cooldown: cooldown
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "devbox.json", content: '{ "packages": [] }')]
  end
  let(:ignored_versions) { [] }
  let(:cooldown) { nil }
  let(:search_url) { "https://search.devbox.sh/v1/search?q=python" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "python",
      version: current_version,
      requirements: [{
        requirement: constraint,
        file: "devbox.json",
        groups: [],
        source: { type: "nixhub" }
      }],
      package_manager: "devbox"
    )
  end

  def stub_nixhub(versions)
    stub_request(:get, search_url).to_return(
      status: 200,
      body: {
        packages: [
          { name: "python", versions: versions }
        ]
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "is registered for the devbox package manager" do
    expect(Dependabot::UpdateCheckers.for_package_manager("devbox")).to eq(described_class)
  end

  context "with a pinned-minor constraint (3.10)" do
    let(:constraint) { "3.10" }
    let(:current_version) { "3.10.13" }

    context "when only a patch bump is available" do
      before { stub_nixhub([{ version: "3.10.13" }, { version: "3.10.19" }]) }

      it "selects the newer patch as the latest version" do
        expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("3.10.19"))
      end

      it "keeps the constraint unchanged (lockfile-only update)" do
        expect(checker.updated_requirements.first[:requirement]).to eq("3.10")
      end
    end

    context "when a newer minor is available" do
      before { stub_nixhub([{ version: "3.10.13" }, { version: "3.11.2" }]) }

      it "selects the newer minor as the latest version" do
        expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("3.11.2"))
      end

      it "rewrites the constraint to the new minor line" do
        expect(checker.updated_requirements.first[:requirement]).to eq("3.11")
      end
    end
  end

  context "with a pinned-exact constraint (3.10.15)" do
    let(:constraint) { "3.10.15" }
    let(:current_version) { "3.10.15" }

    before { stub_nixhub([{ version: "3.10.15" }, { version: "3.10.19" }]) }

    it "rewrites the constraint to the exact new version" do
      expect(checker.updated_requirements.first[:requirement]).to eq("3.10.19")
    end
  end

  context "with the latest sentinel" do
    let(:constraint) { "latest" }
    let(:current_version) { "14.0.0" }
    let(:search_url) { "https://search.devbox.sh/v1/search?q=python" }

    before { stub_nixhub([{ version: "14.0.0" }, { version: "14.1.0" }]) }

    it "advances the latest version" do
      expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("14.1.0"))
    end

    it "keeps the constraint as latest (lockfile-only update)" do
      expect(checker.updated_requirements.first[:requirement]).to eq("latest")
    end
  end

  context "when already on the newest version" do
    let(:constraint) { "3.10" }
    let(:current_version) { "3.10.13" }

    before { stub_nixhub([{ version: "3.10.13" }]) }

    it "leaves the constraint unchanged" do
      expect(checker.updated_requirements.first[:requirement]).to eq("3.10")
    end
  end

  context "with cooldown enabled" do
    let(:constraint) { "3.10" }
    let(:current_version) { "3.10.13" }
    let(:cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 30,
        semver_major_days: 30,
        semver_minor_days: 30,
        semver_patch_days: 30
      )
    end

    context "when the newer version is within the cooldown window" do
      before do
        stub_nixhub(
          [
            { version: "3.10.13", last_updated: 1_600_000_000 },
            { version: "3.11.2", last_updated: Time.now.to_i }
          ]
        )
      end

      it "ignores the recent release and falls back to the current version" do
        expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("3.10.13"))
      end
    end

    context "when the newer version is older than the cooldown window" do
      before do
        stub_nixhub(
          [
            { version: "3.10.13", last_updated: 1_500_000_000 },
            { version: "3.11.2", last_updated: 1_600_000_000 }
          ]
        )
      end

      it "allows the older release" do
        expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("3.11.2"))
      end
    end

    context "when the newer version has no release date" do
      before do
        stub_nixhub(
          [
            { version: "3.10.13", last_updated: 1_500_000_000 },
            { version: "3.11.2" }
          ]
        )
      end

      it "is not held back by cooldown" do
        expect(checker.latest_version).to eq(Dependabot::Devbox::Version.new("3.11.2"))
      end
    end
  end
end
