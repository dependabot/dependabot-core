# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "spec_helper"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/package/package_latest_version_finder"
require "dependabot/git_submodules/update_checker"
require "dependabot/git_submodules/package/package_details_fetcher"
require "dependabot/git_submodules/update_checker/latest_version_finder"

RSpec.describe Dependabot::GitSubmodules::UpdateChecker::LatestVersionFinder do
  let(:branch) { "master" }
  let(:url) { "https://github.com/example/manifesto.git" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
      requirements: [{
        file: ".gitmodules",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: branch, ref: branch }
      }],
      package_manager: "submodules"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options
    )
  end

  let(:cooldown_options) { nil }

  describe "#latest_version that returns latest tag based on git command" do
    subject { checker.latest_tag }

    let(:git_url) { "https://github.com/example/manifesto.git" }

    before do
      stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
        .to_return(
          status: 200,
          body: fixture("upload_packs", "manifesto"),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    it { is_expected.to eq("fe1b155799ab728fae7d3edd5451c35942d711c4") }

    context "when the repo can't be found" do
      before do
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(status: 404)
      end

      it "raises a GitDependenciesNotReachable error" do
        expect { checker.latest_tag }.to raise_error do |error|
          expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
          expect(error.dependency_urls)
            .to eq(["https://github.com/example/manifesto.git"])
        end
      end
    end
  end

  describe "#latest_version with cooldown", :vcr do
    subject { checker.latest_tag }

    before do
      allow(Time).to receive(:now).and_return(Time.parse("2025-06-30T17:30:00.000Z"))
    end

    let(:git_url) { "https://github.com/NuGet/NuGet.Client.git" }
    let(:branch) { "release-6.12.x" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "NuGet",
        version: "95a470a557091cdbdc9f68a178b60bd19329942c",
        requirements: [{
          file: ".gitmodules",
          requirement: nil,
          groups: [],
          source: { type: "git", url: git_url, branch: branch, ref: branch }
        }],
        package_manager: "submodules"
      )
    end

    context "when cooldown is enabled for 90 days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 90
        )
      end

      it { is_expected.to eq("7a84f1ecdb1df83034aa639e496f3b25a16d94ec") }
    end

    context "when cooldown is enabled for 60 days" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 60
        )
      end

      before do
        allow(Time).to receive(:now).and_return(Time.parse("2025-06-01T17:30:00.000Z"))
      end

      it { is_expected.to eq("95a470a557091cdbdc9f68a178b60bd19329942c") }
    end
  end
end
