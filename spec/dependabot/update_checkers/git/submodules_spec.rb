# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/git/submodules"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Git::Submodules do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "sha1",
      requirements: [
        {
          file: ".gitmodules",
          requirement: { url: url, branch: branch },
          groups: []
        }
      ],
      package_manager: "submodules"
    )
  end

  let(:url) { "https://github.com/example/manifesto.git" }
  let(:branch) { "master" }

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      before { allow(checker).to receive(:latest_version).and_return("sha2") }
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      before { allow(checker).to receive(:latest_version).and_return("sha1") }
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
          body: fixture("git", "git-upload-pack-manifesto"),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    it { is_expected.to eq("fe1b155799ab728fae7d3edd5451c35942d711c4") }

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

      it "raises a DependencyFileNotResolvable error" do
        expect { checker.latest_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
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
