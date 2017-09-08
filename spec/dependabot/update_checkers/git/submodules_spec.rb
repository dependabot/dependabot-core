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

    let(:github_url) { "https://api.github.com/repos/example/manifesto" }

    before do
      stub_request(:get, github_url + "/git/refs/heads/master").
        to_return(status: 200,
                  body: fixture("github", "ref.json"),
                  headers: { "content-type" => "application/json" })
    end

    it { is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd") }

    context "when the repo can't be found (e.g., because of a bad branch" do
      before do
        stub_request(:get, github_url + "/git/refs/heads/master").
          to_return(status: 404)
      end

      it "raises a DependencyFileNotResolvable error" do
        expect { checker.latest_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a non-GitHub URL" do
      let(:url) { "https://bitbucket.org/example/manifesto.git" }

      it "raises a useful error (so we add support for other providers" do
        expect { checker.latest_version }.
          to raise_error(/Submodule has non-GitHub/)
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
