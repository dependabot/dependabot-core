# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/base/release_finder"

RSpec.describe Dependabot::MetadataFinders::Base::ReleaseFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      dependency: dependency,
      github_client: github_client
    )
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
  let(:source) do
    { "host" => "github", "repo" => "gocardless/#{dependency_name}" }
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

            context "and the previous release doesn't have a github release" do
              let(:dependency_previous_version) { "0.9.1" }

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
          end

          context "without a previous_version" do
            let(:dependency_previous_version) { nil }

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
      let(:source) do
        { "host" => "gitlab", "repo" => "org/#{dependency_name}" }
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_tags.json") }

      before do
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
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end
end
