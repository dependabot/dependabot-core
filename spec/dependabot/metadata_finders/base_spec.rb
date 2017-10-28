# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/base"

RSpec.describe Dependabot::MetadataFinders::Base do
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [
        { file: "Gemfile", requirement: ">= 0", groups: [], source: nil }
      ],
      previous_version: dependency_previous_version,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_previous_version) { "1.0.0" }
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  before do
    allow(finder).
      to receive(:source).
      and_return("host" => "github", "repo" => "gocardless/#{dependency_name}")
  end

  describe "#source_url" do
    subject { finder.source_url }

    it { is_expected.to eq("https://github.com/gocardless/business") }

    context "with a bitbucket source" do
      before do
        allow(finder).
          to receive(:source).
          and_return("host" => "bitbucket", "repo" => "org/#{dependency_name}")
      end

      it { is_expected.to eq("https://bitbucket.org/org/business") }
    end

    context "without a source" do
      before { allow(finder).to receive(:source).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  context "#commits_url" do
    subject { finder.commits_url }

    context "with a github repo and old/new tags" do
      let(:dependency_previous_version) { "1.3.0" }

      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).to_return(
          status: 200,
          body: fixture("github", "business_tags.json"),
          headers: { "Content-Type" => "application/json" }
        )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "compare/v1.3.0...v1.4.0")
      end
    end

    context "with a github repo and only a new tag" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).to_return(
          status: 200,
          body: fixture("github", "business_tags.json"),
          headers: { "Content-Type" => "application/json" }
        )
      end

      it do
        is_expected.
          to eq("https://github.com/gocardless/business/commits/v1.4.0")
      end
    end

    context "with a github repo and tags with surprising names" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).to_return(
          status: 200,
          body: fixture("github", "prefixed_tags.json"),
          headers: { "Content-Type" => "application/json" }
        )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/business-1.4.0")
      end
    end

    context "with a github repo and tags with no prefix" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).to_return(
          status: 200,
          body: fixture("github", "unprefixed_tags.json"),
          headers: { "Content-Type" => "application/json" }
        )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/1.4.0")
      end
    end

    context "with a github repo and no tags found" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).to_return(
          status: 200,
          body: "[]",
          headers: { "Content-Type" => "application/json" }
        )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/commits")
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tags"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_tags.json") }

      before do
        allow(finder).
          to receive(:source).
          and_return("host" => "gitlab", "repo" => "org/#{dependency_name}")

        stub_request(:get, gitlab_url).
          to_return(status: gitlab_status,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/"\
                            "compare/v1.3.0...v1.4.0")
        end
      end

      context "with only a new tag" do
        let(:dependency_previous_version) { "0.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/commits/v1.4.0")
        end
      end

      context "no tags" do
        let(:dependency_previous_version) { "0.3.0" }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/commits/master")
        end
      end
    end

    context "with a bitbucket source" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/refs/tags"\
        "?pagelen=100"
      end

      let(:bitbucket_status) { 200 }
      let(:bitbucket_response) { fixture("bitbucket", "business_tags.json") }

      before do
        allow(finder).
          to receive(:source).
          and_return("host" => "bitbucket", "repo" => "org/#{dependency_name}")

        stub_request(:get, bitbucket_url).
          to_return(status: bitbucket_status,
                    body: bitbucket_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/"\
                            "branches/compare/v1.4.0..v1.3.0")
        end
      end

      context "with only a new tag" do
        let(:dependency_previous_version) { "0.3.0" }

        it "gets the right URL" do
          is_expected.
            to eq("https://bitbucket.org/org/business/commits/tag/v1.4.0")
        end
      end

      context "no tags" do
        let(:dependency_previous_version) { "0.3.0" }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/commits")
        end
      end

      context "no previous version" do
        let(:dependency_previous_version) { nil }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/commits")
        end
      end
    end

    context "without a recognised source" do
      before { allow(finder).to receive(:source).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  describe "#changelog_url" do
    subject { finder.changelog_url }
    let(:dummy_changelog_finder) do
      instance_double(Dependabot::MetadataFinders::Base::ChangelogFinder)
    end

    it "delegates to ChangelogFinder (and caches the instance)" do
      expected_source =
        { "host" => "github", "repo" => "gocardless/#{dependency_name}" }
      expect(Dependabot::MetadataFinders::Base::ChangelogFinder).
        to receive(:new).
        with(github_client: github_client, source: expected_source).once.
        and_return(dummy_changelog_finder)
      expect(dummy_changelog_finder).
        to receive(:changelog_url).twice.
        and_return("https://example.com//CHANGELOG.md")
      expect(finder.changelog_url).to eq("https://example.com//CHANGELOG.md")
      expect(finder.changelog_url).to eq("https://example.com//CHANGELOG.md")
    end
  end

  describe "#release_url" do
    subject { finder.release_url }
    let(:dummy_release_finder) do
      instance_double(Dependabot::MetadataFinders::Base::ReleaseFinder)
    end

    it "delegates to ReleaseFinder (and caches the instance)" do
      expected_source =
        { "host" => "github", "repo" => "gocardless/#{dependency_name}" }
      expect(Dependabot::MetadataFinders::Base::ReleaseFinder).
        to receive(:new).
        with(
          github_client: github_client,
          source: expected_source,
          dependency: dependency
        ).once.and_return(dummy_release_finder)
      expect(dummy_release_finder).
        to receive(:release_url).twice.
        and_return("https://example.com//RELEASES.md")
      expect(finder.release_url).to eq("https://example.com//RELEASES.md")
      expect(finder.release_url).to eq("https://example.com//RELEASES.md")
    end
  end
end
