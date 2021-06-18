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

        context "and a git@... URL" do
          let(:url) { "git@github.com:gocardless/business" }
          it { is_expected.to eq([]) }

          context "that separates with :/" do
            let(:url) { "git@github.com:/gocardless/business" }
            it { is_expected.to eq([]) }
          end

          context "that separates with /" do
            let(:url) { "git@github.com/gocardless/business" }
            it { is_expected.to eq([]) }
          end
        end
      end

      context "but GitHub returns a 404" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 404)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { tags }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "but GitHub returns a 401" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 401)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { tags }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "but GitHub returns a 500" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 500)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { tags }.to raise_error(Octokit::InternalServerError)
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

        context "when HTTP returns a 500 but git ls-remote succeeds" do
          let(:uri) { "https://github.com/gocardless/business.git" }
          let(:stdout) { fixture("git", "upload_packs", upload_pack_fixture) }

          before do
            stub_request(:get, service_pack_url).to_return(status: 500)

            exit_status = double(success?: true)
            allow(Open3).to receive(:capture3).and_call_original
            allow(Open3).to receive(:capture3).
              with(anything, "git ls-remote #{uri}").
              and_return([stdout, "", exit_status])
          end

          its(:count) { is_expected.to eq(14) }
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

        context "when there is a github.com credential with an @ in the user" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token@github.com",
              "password" => "token"
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

    context "with source code hosted on a HTTP host" do
      let(:url) { "http://bitbucket.org/gocardless/business" }
      let(:service_pack_url) do
        "http://bitbucket.org/gocardless/business.git/info/refs"\
        "?service=git-upload-pack"
      end

      let(:upload_pack_fixture) { "business" }

      its(:count) { is_expected.to eq(14) }
    end
  end

  describe "#ref_names" do
    subject(:ref_names) { checker.ref_names }

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

      context "when HTTP returns a 500 but git ls-remote succeeds" do
        let(:uri) { "https://github.com/gocardless/business.git" }
        let(:stdout) { fixture("git", "upload_packs", upload_pack_fixture) }

        before do
          stub_request(:get, service_pack_url).to_return(status: 500)

          exit_status = double(success?: true)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).
            with(anything, "git ls-remote #{uri}").
            and_return([stdout, "", exit_status])
        end

        it { is_expected.to eq(%w(master rails5)) }
      end

      context "with tags on GitHub" do
        let(:upload_pack_fixture) { "no_versions" }
        it { is_expected.to eq(%w(master imported release)) }
      end

      context "but no tags on GitHub" do
        let(:upload_pack_fixture) { "no_tags" }
        it { is_expected.to eq(%w(master rails5)) }
      end

      context "but GitHub returns a 404" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 404)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { ref_names }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end
    end
  end

  describe "#head_commit_for_ref" do
    subject(:head_commit_for_ref) { checker.head_commit_for_ref(ref) }
    let(:ref) { "v1.0.0" }

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

    let(:service_pack_url) do
      "https://github.com/gocardless/business.git/info/refs"\
      "?service=git-upload-pack"
    end

    let(:upload_pack_fixture) { "business" }

    it "gets the correct commit SHA (not the tag SHA)" do
      expect(head_commit_for_ref).
        to eq("df9f605d7111b6814fe493cf8f41de3f9f0978b2")
    end

    context "when HTTP returns a 500 but git ls-remote succeeds" do
      let(:uri) { "https://github.com/gocardless/business.git" }
      let(:stdout) { fixture("git", "upload_packs", upload_pack_fixture) }

      before do
        stub_request(:get, service_pack_url).to_return(status: 500)

        exit_status = double(success?: true)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return([stdout, "", exit_status])
      end

      it "gets the correct commit SHA (not the tag SHA)" do
        expect(head_commit_for_ref).
          to eq("df9f605d7111b6814fe493cf8f41de3f9f0978b2")
      end
    end

    context "with a branch" do
      let(:ref) { "master" }

      it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }

      context "that doesn't exist" do
        let(:ref) { "nonexistent" }
        it { is_expected.to be_nil }
      end

      context "that is HEAD" do
        let(:ref) { "HEAD" }
        it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }
      end
    end
  end
end
