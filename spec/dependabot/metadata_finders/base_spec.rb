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
      requirement: ">= 0",
      previous_version: dependency_previous_version,
      package_manager: "bundler",
      groups: []
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

    context "with a github repo and tags with surprising names" do
      before do
        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "prefixed_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/business-1.4.0")
      end
    end

    context "with a github repo and tags with no prefix" do
      before do
        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "unprefixed_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/1.4.0")
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
    end

    context "without a recognised source" do
      before { allow(finder).to receive(:source).and_return(nil) }
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

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_files.json") }

      before do
        allow(finder).
          to receive(:source).
          and_return("host" => "gitlab", "repo" => "org/#{dependency_name}")

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

      before do
        allow(finder).
          to receive(:source).
          and_return("host" => "bitbucket", "repo" => "org/#{dependency_name}")

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

    context "without a recognised source" do
      before { allow(finder).to receive(:source).and_return(nil) }
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

          context "and is updating from one version previous" do
            let(:dependency_previous_version) { "1.7.0" }

            it "gets the right URL" do
              expect(subject).
                to eq(
                  "https://github.com/gocardless/business/releases/tag/v1.8.0"
                )
            end

            context "but prefixed" do
              let(:github_response) do
                fixture("github", "prefixed_releases.json")
              end

              it "gets the right URL" do
                expect(subject).
                  to eq(
                    "https://github.com/gocardless/business/releases/tag/"\
                    "business-1.8.0"
                  )
              end
            end

            context "but unprefixed" do
              let(:github_response) do
                fixture("github", "unprefixed_releases.json")
              end

              it "gets the right URL" do
                expect(subject).
                  to eq(
                    "https://github.com/gocardless/business/releases/tag/1.8.0"
                  )
              end
            end

            context "but in the tag_name section" do
              let(:github_response) do
                fixture("github", "unnamed_releases.json")
              end

              it "gets the right URL" do
                expect(subject).
                  to eq(
                    "https://github.com/gocardless/business/releases/tag/"\
                    "v1.8.0"
                  )
              end
            end
          end

          context "and is updating from several versions previous" do
            let(:dependency_previous_version) { "1.5.0" }

            it "gets the right URL" do
              expect(subject).
                to eq("https://github.com/gocardless/business/releases")
            end

            context "to a non-latest version" do
              let(:dependency_version) { "1.7.0" }

              it "gets the right URL" do
                expect(subject).
                  to eq("https://github.com/gocardless/business"\
                        "/releases?after=v1.8.0")
              end
            end
          end

          context "without a previous_version" do
            let(:dependency_previous_version) { nil }

            it "gets the right URL" do
              expect(subject).
                to eq(
                  "https://github.com/gocardless/business/releases/tag/"\
                  "v1.8.0"
                )
            end
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

      context "with the current release" do
        let(:dependency_version) { "1.5.0" }
        let(:dependency_previous_version) { "1.4.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/tags/v1.5.0")
        end

        context "when updating from several versions previous" do
          let(:dependency_previous_version) { "1.3.0" }

          it "gets the right URL" do
            expect(subject).to eq("https://gitlab.com/org/business/tags")
          end
        end
      end

      context "without the current release" do
        let(:dependency_version) { "1.6.0" }
        it { is_expected.to be_nil }
      end
    end

    context "without a recognised source" do
      before { allow(finder).to receive(:source).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end
end
