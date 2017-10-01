# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_commit_checker"

RSpec.describe Dependabot::GitCommitChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      github_access_token: github_access_token
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end

  let(:requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: source }]
  end

  let(:source) do
    {
      type: "git",
      url: "https://github.com/gocardless/business",
      branch: "master",
      ref: "master"
    }
  end

  let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
  let(:github_access_token) { "token" }

  describe "#git_dependency?" do
    subject { checker.git_dependency? }

    context "with a non-git dependency" do
      let(:source) { nil }
      it { is_expected.to eq(false) }
    end

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: nil
        }
      end

      it { is_expected.to eq(true) }
    end
  end

  describe "#commit_in_released_version?" do
    subject { checker.commit_in_released_version?(Gem::Version.new("1.5.0")) }

    context "with a non-git dependency" do
      let(:source) { nil }
      specify { expect { subject }.to raise_error(/Not a git dependency!/) }
    end

    context "with a git dependency that is not pinned" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: nil
        }
      end

      it { is_expected.to eq(false) }
    end

    context "with a git dependency that is pinned" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "df9f605"
        }
      end

      let(:rubygems_url) { "https://rubygems.org/api/v1/gems/business.json" }
      let(:rubygems_response_code) { 200 }
      let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
      before do
        stub_request(:get, rubygems_url).
          to_return(status: rubygems_response_code, body: rubygems_response)
      end

      context "with no rubygems listing" do
        let(:rubygems_response_code) { 404 }
        let(:rubygems_response) { "This rubygem could not be found." }
        it { is_expected.to eq(false) }
      end

      context "with source code not hosted on GitHub" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_bitbucket.json")
        end
        it { is_expected.to eq(false) }
      end

      context "with source code hosted on GitHub" do
        let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
        let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
        let(:tags_url) { repo_url + "/tags?per_page=100" }
        before do
          stub_request(:get, tags_url).to_return(
            status: 200,
            body: tags_response,
            headers: { "Content-Type" => "application/json" }
          )
        end

        context "but no tags on GitHub" do
          let(:tags_response) { [].to_json }
          it { is_expected.to eq(false) }
        end

        context "with tags on GitHub" do
          let(:tags_response) { fixture("github", "business_tags.json") }
          let(:comparison_url) { repo_url + "/compare/v1.5.0...df9f605" }
          before do
            stub_request(:get, comparison_url).
              to_return(
                status: 200,
                body: comparison_response,
                headers: { "Content-Type" => "application/json" }
              )
          end

          context "when the specified reference is not in the release" do
            let(:comparison_response) do
              fixture("github", "commit_compare_diverged.json")
            end
            it { is_expected.to eq(false) }
          end

          context "when the specified reference is included in the release" do
            let(:comparison_response) do
              fixture("github", "commit_compare_behind.json")
            end
            it { is_expected.to eq(true) }
          end
        end
      end
    end
  end

  describe "#pinned?" do
    subject { checker.pinned? }

    let(:source) do
      {
        type: "git",
        url: "https://github.com/gocardless/business",
        branch: branch,
        ref: ref
      }
    end

    context "with a non-git dependency" do
      let(:source) { nil }
      specify { expect { subject }.to raise_error(/Not a git dependency!/) }
    end

    context "with no branch or reference specified" do
      let(:ref) { nil }
      let(:branch) { nil }
      it { is_expected.to eq(false) }
    end

    context "with no reference specified" do
      let(:ref) { nil }
      let(:branch) { "master" }
      it { is_expected.to eq(false) }
    end

    context "with a reference that matches the branch" do
      let(:ref) { "master" }
      let(:branch) { "master" }
      it { is_expected.to eq(false) }
    end

    context "with a reference that does not match the branch" do
      let(:ref) { "v1.0.0" }
      let(:branch) { "master" }
      it { is_expected.to eq(true) }
    end

    context "with no branch specified" do
      let(:branch) { nil }

      context "and a reference that matches the version" do
        let(:ref) { "df9f605" }
        it { is_expected.to eq(true) }
      end

      context "and a reference that does not match the version" do
        before do
          git_url = "https://github.com/gocardless/business.git"
          stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
            to_return(
              status: 200,
              body: fixture("git", "git-upload-pack-manifesto"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        context "and does not match any branch names" do
          let(:ref) { "my_ref" }
          it { is_expected.to eq(true) }
        end

        context "and does match a branch names" do
          let(:ref) { "master" }
          it { is_expected.to eq(false) }
        end

        context "when the source is unreachable" do
          before do
            git_url = "https://github.com/gocardless/business.git"
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(status: 404)
          end
          let(:ref) { "my_ref" }
          it { is_expected.to eq(false) }
        end
      end
    end
  end
end
