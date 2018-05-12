# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_updater"

RSpec.describe Dependabot::PullRequestUpdater do
  subject(:updater) do
    Dependabot::PullRequestUpdater.new(source: source,
                                       base_commit: base_commit,
                                       files: files,
                                       credentials: credentials,
                                       pull_request_number: pull_request_number)
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:base_commit) { "basecommitsha" }
  let(:pull_request_number) { 1 }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile"),
      directory: "files/are/here"
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock"),
      directory: "files/are/here"
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }
  let(:pull_request_url) { watched_repo_url + "/pulls/#{pull_request_number}" }
  let(:branch_url) { watched_repo_url + "/branches/" + branch_name }
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }
  let(:branch_name) { "dependabot/ruby/business-1.5.0" }

  before do
    stub_request(:get, pull_request_url).
      to_return(status: 200,
                body: fixture("github", "pull_request.json"),
                headers: json_header)
    stub_request(:get, branch_url).
      to_return(status: 200,
                body: fixture("github", "branch.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/trees").
      to_return(status: 200,
                body: fixture("github", "create_tree.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/commits").
      to_return(status: 200,
                body: fixture("github", "create_commit.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/git/commits/old_pr_sha").
      to_return(status: 200,
                body: fixture("github", "git_commit.json"),
                headers: json_header)
    stub_request(:patch, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
      to_return(status: 200,
                body: fixture("github", "update_ref.json"),
                headers: json_header)
  end

  describe "#update" do
    context "when the branch doesn't exist" do
      before { stub_request(:get, branch_url).to_return(status: 404) }

      it "doesn't push a commit to GitHub" do
        updater.update
        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/git/trees")
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end

    it "pushes a commit to GitHub" do
      updater.update

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/trees").
        with(body: {
               base_tree: "basecommitsha",
               tree: [
                 {
                   path: "files/are/here/Gemfile",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "gemfiles", "Gemfile")
                 },
                 {
                   path: "files/are/here/Gemfile.lock",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "lockfiles", "Gemfile.lock")
                 }
               ]
             })

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits")
    end

    context "with a submodule" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "manifesto",
            type: "submodule",
            content: "sha1"
          )
        ]
      end

      it "pushes a commit to GitHub" do
        updater.update

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/trees").
          with(body: {
                 base_tree: "basecommitsha",
                 tree: [
                   {
                     path: "manifesto",
                     mode: "160000",
                     type: "commit",
                     sha: "sha1"
                   }
                 ]
               })

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits")
      end
    end

    it "has the right commit message" do
      updater.update

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits").
        with(
          body: {
            parents: ["basecommitsha"],
            tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
            message: "Bump business from 1.4.0 to 1.5.0\n\n"\
                     "Bumps [business](https://github.com/gocardless/business)"\
                     " from 1.4.0 to 1.5.0.\n"\
                     "- [Changelog](https://github.com/gocardless/business/blo"\
                     "b/master/CHANGELOG.md)\n"\
                     "- [Commits](https://github.com/gocardless/business/compa"\
                     "re/v3.0.0...v1.5.0)"
          }
        )
    end

    context "with author details" do
      subject(:updater) do
        Dependabot::PullRequestUpdater.new(
          source: source,
          base_commit: base_commit,
          files: files,
          credentials: credentials,
          pull_request_number: pull_request_number,
          author_details: {
            email: "support@dependabot.com",
            name: "dependabot"
          }
        )
      end

      it "passes the author details to GitHub" do
        updater.update

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits").
          with(body: {
                 parents: anything,
                 tree: anything,
                 message: anything,
                 author: { email: "support@dependabot.com", name: "dependabot" }
               })
      end

      context "with a signature key" do
        subject(:updater) do
          described_class.new(
            source: source,
            base_commit: base_commit,
            files: files,
            credentials: credentials,
            pull_request_number: pull_request_number,
            author_details: {
              email: "support@dependabot.com",
              name: "dependabot"
            },
            signature_key: signature_key
          )
        end
        let(:signature_key) { fixture("keys", "pgp.key") }
        let(:public_key) { fixture("keys", "pgp.pub") }
        let(:text_to_sign) do
          "tree cd8274d15fa3ae2ab983129fb037999f264ba9a7\n"\
          "parent basecommitsha\n"\
          "author dependabot <support@dependabot.com> 978307200 +0000\n"\
          "committer dependabot <support@dependabot.com> 978307200 +0000\n"\
          "\n"\
          "Bump business from 1.4.0 to 1.5.0\n"\
          "\n"\
          "Bumps [business](https://github.com/gocardless/business) from "\
          "1.4.0 to 1.5.0.\n"\
          "- [Changelog](https://github.com/gocardless/business/blob/"\
          "master/CHANGELOG.md)\n"\
          "- [Commits](https://github.com/gocardless/business/compare/"\
          "v3.0.0...v1.5.0)"
        end
        before { allow(Time).to receive(:now).and_return(Time.new(2001, 1, 1)) }

        it "passes the author details and signature to GitHub" do
          updater.update

          expect(WebMock).
            to have_requested(:post, "#{watched_repo_url}/git/commits").
            with(
              body: {
                parents: anything,
                tree: anything,
                message: anything,
                author: {
                  email: "support@dependabot.com",
                  name: "dependabot",
                  date: "2001-01-01T00:00:00Z"
                },
                signature: instance_of(String)
              }
            )
        end

        it "signs the correct text, correctly" do
          updater.update

          expect(WebMock).to(
            have_requested(:post, "#{watched_repo_url}/git/commits").
              with do |req|
                signature = JSON.parse(req.body)["signature"]
                valid_sig = false

                Dir.mktmpdir do |dir|
                  GPGME::Engine.home_dir = dir
                  GPGME::Key.import(public_key)

                  crypto = GPGME::Crypto.new(armor: true)
                  crypto.verify(signature, signed_text: text_to_sign) do |sig|
                    valid_sig = sig.valid?
                  end
                end

                valid_sig
              end
          )
        end
      end
    end

    it "updates the PR's branch to point to that commit" do
      updater.update

      expect(WebMock).
        to have_requested(
          :patch, "#{watched_repo_url}/git/refs/heads/#{branch_name}"
        ).with(
          body: {
            sha: "7638417db6d59f3c431d3e1f261cc637155684cd",
            force: true
          }
        )
    end

    it "returns details of the updated branch" do
      expect(updater.update.object.sha).
        to eq("1e2d2afe8320998baecdfe127a49dca9a6650e07")
    end

    context "when the branch gets deleted mid-flow" do
      before do
        stub_request(
          :patch,
          "#{watched_repo_url}/git/refs/heads/#{branch_name}"
        ).to_return(status: 422,
                    body: fixture("github", "update_ref_error.json"),
                    headers: json_header)
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end
  end
end
