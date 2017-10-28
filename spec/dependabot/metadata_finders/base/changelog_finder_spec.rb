# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/metadata_finders/base/changelog_finder"

RSpec.describe Dependabot::MetadataFinders::Base::ChangelogFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      github_client: github_client,
      dependency: dependency
    )
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:source) { { "host" => "github", "repo" => "gocardless/business" } }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      previous_version: dependency_previous_version,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_version) { "1.0.0" }

  describe "#changelog_url" do
    subject { finder.changelog_url }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with a changelog" do
        let(:github_response) { fixture("github", "business_files.json") }

        it "gets the right URL" do
          expect(subject).
            to eq(
              "https://github.com/gocardless/business/blob/master/CHANGELOG.md"
            )
        end

        it "caches the call to GitHub" do
          finder.changelog_url
          finder.changelog_url
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "without a changelog" do
        let(:github_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        it { is_expected.to be_nil }
      end

      context "for a git dependency" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:dependency_requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: new_ref
              }
            }
          ]
        end
        let(:dependency_previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: old_ref
              }
            }
          ]
        end
        let(:new_ref) { "master" }
        let(:old_ref) { "master" }

        it { is_expected.to be_nil }

        context "when the ref has changed" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "finds the changelog as normal" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/"\
                    "CHANGELOG.md")
          end
        end
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_files.json") }
      let(:source) { { "host" => "gitlab", "repo" => "org/business" } }

      before do
        stub_request(:get, gitlab_url).
          to_return(status: gitlab_status,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://gitlab.com/org/business/blob/master/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:gitlab_status) { 404 }
        let(:gitlab_response) { fixture("gitlab", "not_found.json") }
        it { is_expected.to be_nil }
      end
    end

    context "with a bitbucket source" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/src"\
        "?pagelen=100"
      end

      let(:bitbucket_status) { 200 }
      let(:bitbucket_response) { fixture("bitbucket", "business_files.json") }
      let(:source) { { "host" => "bitbucket", "repo" => "org/business" } }

      before do
        stub_request(:get, bitbucket_url).
          to_return(status: bitbucket_status,
                    body: bitbucket_response,
                    headers: { "Content-Type" => "application/json" })
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://bitbucket.org/org/business/src/master/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:bitbucket_status) { 404 }
        it { is_expected.to be_nil }
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end
end
