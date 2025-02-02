# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/update_checker/latest_version_finder"

RSpec.describe Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder do
  before do
    stub_request(:get, Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder::RELEASES_INDEX_URL)
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: releases_index_body)

    stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("releases", "releases-8.0.json"))

    stub_request(:get, "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/9.0/releases.json")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: fixture("releases", "releases-9.0.json"))
  end

  let(:releases_index_body) { fixture("releases", "releases-index-small.json") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dotnet-sdk",
      version: "8.0.300",
      requirements: [],
      package_manager: "dotnet_sdk",
      metadata: {
        allow_prerelease: false
      }
    )
  end
  let(:ignored_versions) { [] }

  describe "#latest_version" do
    subject(:latest_version) do
      described_class.new(dependency: dependency, ignored_versions: ignored_versions).latest_version
    end

    it { is_expected.to eq(Dependabot::Version.new("8.0.402")) }

    context "when the user is on the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: "8.0.402",
          requirements: [],
          package_manager: "dotnet_sdk",
          metadata: {
            allow_prerelease: false
          }
        )
      end

      it { is_expected.to eq(Dependabot::Version.new("8.0.402")) }
    end

    context "when the latest version is ignored" do
      let(:ignored_versions) { [">= 8.0.402"] }

      it { is_expected.to eq(Dependabot::Version.new("8.0.401")) }
    end

    context "when later versions are ignored" do
      let(:ignored_versions) { ["> 8.0.300"] }

      it { is_expected.to eq(Dependabot::Version.new("8.0.300")) }
    end

    context "when the latest version is a pre-release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dotnet-sdk",
          version: "8.0.300",
          requirements: [],
          package_manager: "dotnet_sdk",
          metadata: {
            allow_prerelease: true
          }
        )
      end

      it { is_expected.to eq(Dependabot::Version.new("9.0.100.pre.rc.1.24452.12")) }

      context "when it is ignored" do
        let(:ignored_versions) { [">= 9.0.100.a"] }

        it { is_expected.to eq(Dependabot::Version.new("8.0.402")) }
      end
    end

    context "when there are no available versions" do
      before do
        stub_request(:get, Dependabot::DotnetSdk::UpdateChecker::LatestVersionFinder::RELEASES_INDEX_URL)
          .to_return(status: 200, body: fixture("releases", "releases-index-empty.json"))
      end

      it { is_expected.to be_nil }
    end
  end
end
