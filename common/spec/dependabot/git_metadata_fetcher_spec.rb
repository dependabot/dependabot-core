# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_ref"
require "dependabot/git_tag_with_detail"

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
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    context "with source code hosted on GitHub" do
      let(:service_pack_url) do
        "https://github.com/gocardless/business.git/info/refs" \
          "?service=git-upload-pack"
      end
      let(:upload_pack_fixture) { "no_tags" }

      context "when there are no tags on GitHub" do
        let(:upload_pack_fixture) { "no_tags" }

        it { is_expected.to eq([]) }

        context "when using a git@... URL" do
          let(:url) { "git@github.com:gocardless/business" }

          it { is_expected.to eq([]) }

          context "when separating with :/" do
            let(:url) { "git@github.com:/gocardless/business" }

            it { is_expected.to eq([]) }
          end

          context "when separating with /" do
            let(:url) { "git@github.com/gocardless/business" }

            it { is_expected.to eq([]) }
          end
        end
      end

      context "when GitHub returns a 404" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 404)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { tags }
            .to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "when GitHub returns a 401" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 401)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { tags }
            .to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "when GitHub returns a 500" do
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
            Dependabot::GitRef.new(
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
            allow(Open3).to receive(:capture3)
              .with(anything, "git ls-remote #{uri}")
              .and_return([stdout, "", exit_status])
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
        "https://bitbucket.org/gocardless/business.git/info/refs" \
          "?service=git-upload-pack"
      end

      let(:upload_pack_fixture) { "business" }

      its(:count) { is_expected.to eq(14) }
    end

    context "with source code hosted on a HTTP host" do
      let(:url) { "http://bitbucket.org/gocardless/business" }
      let(:service_pack_url) do
        "http://bitbucket.org/gocardless/business.git/info/refs" \
          "?service=git-upload-pack"
      end

      let(:upload_pack_fixture) { "business" }

      its(:count) { is_expected.to eq(14) }
    end
  end

  describe "#ref_names" do
    subject(:ref_names) { checker.ref_names }

    before do
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    context "with source code hosted on GitHub" do
      let(:service_pack_url) do
        "https://github.com/gocardless/business.git/info/refs" \
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
          allow(Open3).to receive(:capture3)
            .with(anything, "git ls-remote #{uri}")
            .and_return([stdout, "", exit_status])
        end

        it { is_expected.to eq(%w(master rails5)) }
      end

      context "with tags on GitHub" do
        let(:upload_pack_fixture) { "no_versions" }

        it { is_expected.to eq(%w(master imported release)) }
      end

      context "when there are no tags on GitHub" do
        let(:upload_pack_fixture) { "no_tags" }

        it { is_expected.to eq(%w(master rails5)) }
      end

      context "when GitHub returns a 404" do
        let(:uri) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, service_pack_url).to_return(status: 404)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{uri}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { ref_names }
            .to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end
    end
  end

  describe "#head_commit_for_ref" do
    subject(:head_commit_for_ref) { checker.head_commit_for_ref(ref) }

    let(:ref) { "v1.0.0" }
    let(:service_pack_url) do
      "https://github.com/gocardless/business.git/info/refs" \
        "?service=git-upload-pack"
    end
    let(:upload_pack_fixture) { "business" }

    before do
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    it "gets the correct commit SHA (not the tag SHA)" do
      expect(head_commit_for_ref)
        .to eq("df9f605d7111b6814fe493cf8f41de3f9f0978b2")
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
        expect(head_commit_for_ref)
          .to eq("df9f605d7111b6814fe493cf8f41de3f9f0978b2")
      end
    end

    context "with a branch" do
      let(:ref) { "master" }

      it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }

      context "when the reference doesn't exist" do
        let(:ref) { "nonexistent" }

        it { is_expected.to be_nil }
      end

      context "when the reference is HEAD" do
        let(:ref) { "HEAD" }

        it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }
      end
    end
  end

  describe "#refs_for_tag_with_detail" do
    context "when upload_tag_with_detail contains valid data" do
      let(:upload_tag_with_detail) do
        <<~TAGS
          v1.0.0 2023-01-01
          v1.1.0 2023-02-01
        TAGS
      end

      before do
        allow(checker).to receive(:upload_tag_with_detail).and_return(upload_tag_with_detail)
      end

      it "parses the tags and release dates into GitTagWithDetail objects" do
        result = checker.refs_for_tag_with_detail

        expect(result.size).to eq(2)
        expect(result.first).to be_a(Dependabot::GitTagWithDetail)
        expect(result.first.tag).to eq("v1.0.0")
        expect(result.first.release_date).to eq("2023-01-01")
        expect(result.last.tag).to eq("v1.1.0")
        expect(result.last.release_date).to eq("2023-02-01")
      end
    end

    context "when upload_tag_with_detail is empty" do
      before do
        allow(checker).to receive(:upload_tag_with_detail).and_return("")
      end

      it "returns an empty array" do
        result = checker.refs_for_tag_with_detail
        expect(result).to eq([])
      end
    end

    context "when upload_tag_with_detail is nil" do
      before do
        allow(checker).to receive(:upload_tag_with_detail).and_return(nil)
      end

      it "returns an empty array" do
        result = checker.refs_for_tag_with_detail
        expect(result).to eq([])
      end
    end

    context "when upload_tag_with_detail contains invalid data" do
      let(:upload_tag_with_detail) do
        <<~TAGS
          invalid_line
          v1.0.0
        TAGS
      end

      before do
        allow(checker).to receive(:upload_tag_with_detail).and_return(upload_tag_with_detail)
      end

      it "skips invalid lines and parses valid ones" do
        result = checker.refs_for_tag_with_detail

        expect(result.size).to eq(2) # No valid tag-release pairs
      end
    end

    describe "#fetch_tags_with_detail_from_git_for" do
      let(:url) { "https://github.com/dependabot/dependabot-core.git" }
      let(:credentials) { [] }

      context "when the repository is cloned successfully" do
        before do
          allow(Open3).to receive(:capture3).with(any_args).and_wrap_original do |_, _env, command|
            if command.include?("git clone")
              ["", "", instance_double(Process::Status, success?: true)]
            elsif command.include?("git for-each-ref")
              ["v1.0.0 2023-01-01\nv1.1.0 2023-02-01", "", instance_double(Process::Status, success?: true)]
            else
              raise "Unexpected command: #{command}"
            end
          end
        end

        it "returns the tags sorted by creation date" do
          result = checker.send(:fetch_tags_with_detail_from_git_for, url)
          expect(result.status).to eq(200)
          expect(result.body).to eq("v1.0.0 2023-01-01\nv1.1.0 2023-02-01")
        end
      end

      context "when cloning the repository fails" do
        before do
          allow(Open3).to receive(:capture3).with(any_args).and_wrap_original do |_, _env, command|
            if command.include?("git clone")
              ["", "Cloning failed", instance_double(Process::Status, success?: false)]
            else
              raise "Unexpected command: #{command}"
            end
          end
        end

        it "returns a 500 status with the error message" do
          result = checker.send(:fetch_tags_with_detail_from_git_for, url)
          expect(result.status).to eq(500)
          expect(result.body).to eq("Cloning failed")
        end
      end

      context "when fetching tags fails" do
        before do
          allow(Open3).to receive(:capture3).with(any_args).and_wrap_original do |_, _env, command|
            if command.include?("git clone")
              ["", "", instance_double(Process::Status, success?: true)]
            elsif command.include?("git for-each-ref")
              ["", "Fetching tags failed", instance_double(Process::Status, success?: false)]
            else
              raise "Unexpected command: #{command}"
            end
          end
        end

        it "returns a 500 status with the error message" do
          result = checker.send(:fetch_tags_with_detail_from_git_for, url)
          expect(result.status).to eq(500)
          expect(result.body).to eq("Fetching tags failed")
        end
      end

      context "when git is not installed" do
        before do
          allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, "No such file or directory - git")
        end

        it "returns a 500 status with the error message" do
          result = checker.send(:fetch_tags_with_detail_from_git_for, url)
          expect(result.status).to eq(500)
          expect(result.body).to eq("No such file or directory - No such file or directory - git")
        end
      end
    end
  end
end
