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

  describe "#branch_or_ref_in_release?" do
    subject do
      checker.branch_or_ref_in_release?(Gem::Version.new("1.5.0"))
    end

    context "with a non-git dependency" do
      let(:source) { nil }
      specify { expect { subject }.to raise_error(/Not a git dependency!/) }
    end

    context "with a git dependency" do
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

          context "with an unpinned dependency" do
            let(:source) do
              {
                type: "git",
                url: "https://github.com/gocardless/business",
                branch: "master",
                ref: nil
              }
            end
            let(:comparison_url) { repo_url + "/compare/v1.5.0...master" }
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

  describe "#pinned_ref_looks_like_version?" do
    subject { checker.pinned_ref_looks_like_version? }

    context "with a non-pinned dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "master"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with a non-version pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "1a21311"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with no ref" do
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
  end

  describe "#local_tag_for_version" do
    subject { checker.local_tag_for_version(version) }
    let(:version) { Gem::Version.new("1.4.0") }
    let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
    let(:tags_url) { repo_url + "/tags?per_page=100" }
    before do
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags_response,
        headers: { "Content-Type" => "application/json" }
      )
    end

    context "with no tags on GitHub" do
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "with a non-GitHub URL" do
      before { source.merge(url: "https://example.com") }
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "with tags on GitHub" do
      context "but no version tags" do
        let(:tags_response) do
          fixture("github", "business_tags_no_versions.json")
        end
        it { is_expected.to eq(nil) }
      end

      context "with version tags" do
        let(:tags_response) { fixture("github", "business_tags.json") }
        its([:tag]) { is_expected.to eq("v1.4.0") }
        its([:commit_sha]) do
          is_expected.to eq("26f4887ec647493f044836363537e329d9d213aa")
        end
      end

      context "with prefixed tags" do
        let(:tags_response) { fixture("github", "prefixed_tags.json") }
        its([:tag]) { is_expected.to eq("business-1.4.0") }
        its([:commit_sha]) do
          is_expected.to eq("26f4887ec647493f044836363537e329d9d213aa")
        end
      end
    end
  end

  describe "#local_tag_for_latest_version" do
    subject { checker.local_tag_for_latest_version }
    let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
    let(:tags_url) { repo_url + "/tags?per_page=100" }
    before do
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags_response,
        headers: { "Content-Type" => "application/json" }
      )
    end

    context "with no tags on GitHub" do
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "with a non-GitHub URL" do
      before { source.merge(url: "https://example.com") }
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "with tags on GitHub" do
      context "but no version tags" do
        let(:tags_response) do
          fixture("github", "business_tags_no_versions.json")
        end
        it { is_expected.to eq(nil) }
      end

      context "with version tags" do
        let(:tags_response) { fixture("github", "business_tags.json") }
        its([:tag]) { is_expected.to eq("v1.5.0") }
        its([:commit_sha]) do
          is_expected.to eq("55d39bf3042fac0b770bca2bfb200cfdffcd0175")
        end
      end

      context "with prefixed tags" do
        let(:tags_response) { fixture("github", "prefixed_tags.json") }
        its([:tag]) { is_expected.to eq("business-21.4.0") }
        its([:commit_sha]) do
          is_expected.to eq("55d39bf3042fac0b770bca2bfb200cfdffcd0175")
        end
      end
    end
  end
end
