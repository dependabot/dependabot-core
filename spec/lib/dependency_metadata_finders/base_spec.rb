# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/dependency"
require "bump/dependency_metadata_finders/base"

RSpec.describe Bump::DependencyMetadataFinders::Base do
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:dependency) do
    Bump::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_previous_version) { nil }
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  before do
    allow(finder).
      to receive(:github_repo).
      and_return("gocardless/#{dependency_name}")
  end

  describe "#github_repo_url" do
    subject { finder.github_repo_url }
    it { is_expected.to eq("https://github.com/gocardless/business") }

    context "without a github repo" do
      before { allow(finder).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  context "#github_compare_url" do
    subject { finder.github_compare_url }

    context "with a github repo and old/new tags" do
      let(:dependency_previous_version) { "1.3.0" }

      before do
        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "business_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "compare/v1.3.0...v1.4.0")
      end
    end

    context "with a github repo and only a new tag" do
      before do
        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "business_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.
          to eq("https://github.com/gocardless/business/commits/v1.4.0")
      end
    end

    context "with a github repo and no tags found" do
      before do
        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: "[]",
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/commits")
      end
    end

    context "without a github repo" do
      before { allow(finder).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

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

        it "caches the call to github" do
          2.times { finder.changelog_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "without a changelog" do
        let(:github_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }

        it "caches the call to github" do
          2.times { finder.changelog_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        it { is_expected.to be_nil }
      end
    end

    context "without a github repo" do
      before { allow(finder).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  describe "#release_url" do
    subject { finder.release_url }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/releases"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with releases" do
        let(:github_response) { fixture("github", "business_releases.json") }

        context "when the release is present" do
          let(:dependency_version) { "1.8.0" }

          it "gets the right URL" do
            expect(subject).
              to eq(
                "https://github.com/gocardless/business/releases/tag/v1.8.0"
              )
          end
        end

        context "when the release is not present" do
          let(:dependency_version) { "1.4.0" }
          it { is_expected.to be_nil }
        end

        it "caches the call to github" do
          2.times { finder.release_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "without any releases" do
        let(:github_response) { [].to_json }

        it { is_expected.to be_nil }

        it "caches the call to github" do
          2.times { finder.release_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        it { is_expected.to be_nil }
      end
    end

    context "without a github repo" do
      before { allow(finder).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end
end
