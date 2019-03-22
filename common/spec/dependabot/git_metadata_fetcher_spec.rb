# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_metadata_fetcher"

RSpec.describe Dependabot::GitMetadataFetcher do
  let(:checker) { described_class.new(url: url, credentials: credentials) }

  let(:url) { "https://github.com/gocardless/business" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }, {
      "some" => "irrelevant credential"
    }]
  end

  describe "#tags" do
    subject(:tags) { checker.tags }

    before do
      stub_request(:get, service_pack_url).
        to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    context "with source code hosted on GitHub" do
      let(:service_pack_url) do
        "https://github.com/gocardless/business.git/info/refs"\
        "?service=git-upload-pack"
      end
      let(:upload_pack_fixture) { "no_tags" }

      context "but no tags on GitHub" do
        let(:upload_pack_fixture) { "no_tags" }
        it { is_expected.to eq([]) }
      end

      context "but GitHub returns a 404" do
        before { stub_request(:get, service_pack_url).to_return(status: 404) }

        it "raises a helpful error" do
          expect { tags }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "with tags" do
        let(:upload_pack_fixture) { "business" }

        its(:count) { is_expected.to eq(14) }

        it "has correct details of the tag SHA and commit SHA" do
          expect(tags.first).to eq(
            OpenStruct.new(
              name: "v1.0.0",
              tag_sha: "c5bf1bd47935504072ac0eba1006cf4d67af6a7a",
              commit_sha: "df9f605d7111b6814fe493cf8f41de3f9f0978b2"
            )
          )
        end

        context "when there is no github.com credential" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "bitbucket.org",
              "username" => "x-access-token",
              "password" => "token"
            }]
          end

          its(:count) { is_expected.to eq(14) }
        end

        context "when there is a github.com credential without a password" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }]
          end

          its(:count) { is_expected.to eq(14) }
        end
      end
    end

    context "with source code not hosted on GitHub" do
      let(:url) { "https://bitbucket.org/gocardless/business" }
      let(:service_pack_url) do
        "https://bitbucket.org/gocardless/business.git/info/refs"\
        "?service=git-upload-pack"
      end

      let(:upload_pack_fixture) { "business" }

      its(:count) { is_expected.to eq(14) }
    end
  end
end
