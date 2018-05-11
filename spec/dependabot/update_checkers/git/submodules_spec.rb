# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/git/submodules"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Git::Submodules do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [
        {
          "type" => "git",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
      requirements: [
        {
          file: ".gitmodules",
          requirement: nil,
          groups: [],
          source: { type: "git", url: url, branch: branch, ref: branch }
        }
      ],
      package_manager: "submodules"
    )
  end

  let(:url) { "https://github.com/example/manifesto.git" }
  let(:branch) { "master" }

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      before { allow(checker).to receive(:latest_version).and_return("sha2") }
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      before do
        allow(checker).
          to receive(:latest_version).
          and_return("2468a02a6230e59ed1232d95d1ad3ef157195b03")
      end
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:git_url) { "https://github.com/example/manifesto.git" }

    before do
      stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
        to_return(
          status: 200,
          body: fixture("git", "upload_packs", "manifesto"),
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
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          to_return(status: 404)
      end

      it "raises a GitDependenciesNotReachable error" do
        expect { checker.latest_version }.to raise_error do |error|
          expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
          expect(error.dependency_urls).
            to eq(["https://github.com/example/manifesto.git"])
        end
      end
    end

    context "when the reference can't be found" do
      let(:branch) { "bad-branch" }

      it "raises a GitDependencyReferenceNotFound error" do
        expect { checker.latest_version }.
          to raise_error do |error|
            expect(error).to be_a(Dependabot::GitDependencyReferenceNotFound)
            expect(error.dependency).to eq("manifesto")
          end
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("sha2") }
    it { is_expected.to eq("sha2") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }
    it { is_expected.to eq(dependency.requirements) }
  end
end
