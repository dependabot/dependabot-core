# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

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
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  describe "#latest_version" do
    subject { checker.latest_version }

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

    context "when the repo doesn't have a .git suffix" do
      let(:url) { "https://github.com/example/manifesto" }

      it { is_expected.to eq("fe1b155799ab728fae7d3edd5451c35942d711c4") }
    end

    context "when the repo can't be found" do
      before do
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(status: 404)
      end

      it "raises a GitDependenciesNotReachable error" do
        expect { checker.latest_version }.to raise_error do |error|
          expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
          expect(error.dependency_urls)
            .to eq(["https://github.com/example/manifesto.git"])
        end
      end
    end

    context "when the reference can't be found" do
      let(:branch) { "bad-branch" }

      it "raises a GitDependencyReferenceNotFound error" do
        expect { checker.latest_version }
          .to raise_error do |error|
            expect(error).to be_a(Dependabot::GitDependencyReferenceNotFound)
            expect(error.dependency).to eq("manifesto")
          end
      end
    end
  end
end
