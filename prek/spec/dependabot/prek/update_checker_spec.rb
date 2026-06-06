# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/prek/update_checker"
require "dependabot/prek/metadata_finder"
require "dependabot/prek/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Prek::UpdateChecker do
  let(:upload_pack_fixture) { "pre-commit-hooks" }
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs?service=git-upload-pack"
  end
  let(:reference) { "v4.4.0" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:dependency_version) do
    return unless Dependabot::Prek::Version.correct?(reference)

    Dependabot::Prek::Version.new(reference).to_s
  end
  let(:dependency_name) { "pre-commit/pre-commit-hooks" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/#{dependency_name}",
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "prek.toml",
        source: dependency_source
      }],
      package_manager: "prek"
    )
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  it_behaves_like "an update checker"

  it "is registered as the update checker for the prek package manager" do
    expect(Dependabot::UpdateCheckers.for_package_manager("prek")).to eq(described_class)
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "returns the latest tagged version as a prek version" do
      expect(latest_version).to be_a(Dependabot::Prek::Version)
      expect(latest_version.to_s).to eq("6.0.0")
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "bumps the git ref to the latest version tag" do
      expect(updated_requirements.first[:source][:ref]).to eq("v6.0.0")
    end
  end
end
