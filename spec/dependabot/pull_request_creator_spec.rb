# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator"

RSpec.describe Dependabot::PullRequestCreator do
  subject(:creator) do
    described_class.new(
      repo: repo,
      base_commit: base_commit,
      dependencies: [dependency],
      files: files,
      github_client: github_client,
      custom_labels: custom_labels
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ]
    )
  end
  let(:custom_labels) { nil }
  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile, gemfile_lock] }
  let(:base_commit) { "basecommitsha" }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock")
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{repo}" }
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }

  let(:dummy_message_builder) do
    instance_double(described_class::MessageBuilder)
  end
  before do
    allow(described_class::MessageBuilder).
      to receive(:new).and_return(dummy_message_builder)
    allow(dummy_message_builder).
      to receive(:commit_message).
      and_return("Commit msg")
    allow(dummy_message_builder).to receive(:pr_name).and_return("PR name")
    allow(dummy_message_builder).to receive(:pr_message).and_return("PR msg")
  end

  before do
    stub_request(:get, watched_repo_url).
      to_return(status: 200,
                body: fixture("github", "bump_repo.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
      to_return(status: 404,
                body: fixture("github", "not_found.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/trees").
      to_return(status: 200,
                body: fixture("github", "create_tree.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/commits").
      to_return(status: 200,
                body: fixture("github", "create_commit.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/refs").
      to_return(status: 200,
                body: fixture("github", "create_ref.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/labels?per_page=100").
      to_return(status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/pulls").
      to_return(status: 200,
                body: fixture("github", "create_pr.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/issues/1347/labels").
      to_return(status: 200,
                body: fixture("github", "create_label.json"),
                headers: json_header)
  end

  describe "#create" do
    context "without a previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          package_manager: "bundler",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it "errors out on initialization" do
        expect { creator }.to raise_error(/must have a/)
      end
    end

    it "pushes a commit to GitHub" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/trees").
        with(body: {
               base_tree: "basecommitsha",
               tree: [
                 {
                   path: "Gemfile",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "gemfiles", "Gemfile")
                 },
                 {
                   path: "Gemfile.lock",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "lockfiles", "Gemfile.lock")
                 }
               ]
             })

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits").
        with(body: {
               parents: ["basecommitsha"],
               tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
               message: "Commit msg"
             })
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
        creator.create

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

    context "when the branch already exists" do
      before do
        stub_request(:get, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
          to_return(status: 200,
                    body: [{ ref: "refs/heads/#{branch_name}" }].to_json,
                    headers: json_header)
      end

      context "but a PR to this branch doesn't" do
        before do
          url = "#{watched_repo_url}/pulls?head=gocardless:#{branch_name}"\
                "&state=all"
          stub_request(:get, url).
            to_return(status: 200, body: "[]", headers: json_header)
          stub_request(
            :patch,
            "#{watched_repo_url}/git/refs/heads/#{branch_name}"
          ).to_return(
            status: 200,
            body: fixture("github", "update_ref.json"),
            headers: json_header
          )
        end

        it "creates a PR with the right details" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{watched_repo_url}/pulls").
            with(
              body: {
                base: "master",
                head: "dependabot/bundler/business-1.5.0",
                title: "PR name",
                body: "PR msg"
              }
            )
        end
      end

      context "and a PR to this branch already exists" do
        before do
          url = "#{watched_repo_url}/pulls?head=gocardless:#{branch_name}"\
                "&state=all"
          stub_request(:get, url).
            to_return(status: 200, body: "[{}]", headers: json_header)
        end

        it "returns nil" do
          expect(creator.create).to be_nil

          expect(WebMock).
            to_not have_requested(:post, "#{watched_repo_url}/pulls")
        end
      end
    end

    context "when a branch with a name that is a superstring exists" do
      before do
        stub_request(:get, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
          to_return(status: 200,
                    body: [{ ref: "refs/heads/#{branch_name}.beta3" }].to_json,
                    headers: json_header)
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-1.5.0",
              title: "PR name",
              body: "PR msg"
            }
          )
      end
    end

    context "with author details" do
      subject(:creator) do
        described_class.new(
          repo: repo,
          base_commit: base_commit,
          dependencies: [dependency],
          files: files,
          github_client: github_client,
          author_details: {
            email: "support@dependabot.com",
            name: "dependabot"
          }
        )
      end

      it "passes the author details to GitHub" do
        creator.create

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
        subject(:creator) do
          described_class.new(
            repo: repo,
            base_commit: base_commit,
            dependencies: [dependency],
            files: files,
            github_client: github_client,
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
          "Commit msg"
        end
        before { allow(Time).to receive(:now).and_return(Time.new(2001, 1, 1)) }

        it "passes the author details and signature to GitHub" do
          creator.create

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
          creator.create

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

    it "creates a branch for that commit" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/refs").
        with(body: {
               ref: "refs/heads/dependabot/bundler/business-1.5.0",
               sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
             })
    end

    it "creates a PR with the right details" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/pulls").
        with(
          body: {
            base: "master",
            head: "dependabot/bundler/business-1.5.0",
            title: "PR name",
            body: "PR msg"
          }
        )
    end

    it "labels the PR" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/issues/1347/labels").
        with(body: '["dependencies"]')
    end

    it "returns details of the created pull request" do
      expect(creator.create.title).to eq("new-feature")
      expect(creator.create.number).to eq(1347)
    end

    context "with a target branch" do
      subject(:creator) do
        described_class.new(
          repo: repo,
          base_commit: base_commit,
          target_branch: "my_branch",
          dependencies: [dependency],
          files: files,
          github_client: github_client
        )
      end
      let(:branch_name) { "dependabot/bundler/my_branch/business-1.5.0" }

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "my_branch",
              head: "dependabot/bundler/my_branch/business-1.5.0",
              title: "PR name",
              body: "PR msg"
            }
          )
      end
    end

    context "when the 'dependencies' label doesn't yet exist" do
      before do
        stub_request(:get, "#{watched_repo_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_without_dependencies.json"),
                    headers: json_header)
        stub_request(:post, "#{watched_repo_url}/labels").
          to_return(status: 201,
                    body: fixture("github", "create_label.json"),
                    headers: json_header)
      end

      it "creates a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/labels").
          with(
            body: {
              name: "dependencies",
              color: "0025ff",
              description: "Pull requests that update a dependency file"
            }
          )
      end

      context "when there's a race and we lose" do
        before do
          stub_request(:post, "#{watched_repo_url}/labels").
            to_return(status: 422,
                      body: fixture("github", "label_already_exists.json"),
                      headers: json_header)
        end

        it "quietly ignores losing the race" do
          expect(creator.create.title).to eq("new-feature")
        end
      end
    end

    context "when there is a custom dependencies label" do
      before do
        stub_request(:get, "#{watched_repo_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_with_custom.json"),
                    headers: json_header)
      end

      it "does not create a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/labels")
      end

      it "labels the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/issues/1347/labels").
          with(body: '["Dependency: Gems"]')
      end
    end

    context "when a custom dependencies label has been requested" do
      let(:custom_labels) { ["wontfix"] }

      it "does not create a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/labels")
      end

      it "labels the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/issues/1347/labels").
          with(body: '["wontfix"]')
      end

      context "that doesn't exist" do
        let(:custom_labels) { ["non-existent"] }

        # Alternatively we could create the label (current choise isn't fixed)
        it "does not create any labels" do
          creator.create

          expect(WebMock).
            to_not have_requested(:post, "#{watched_repo_url}/labels")
        end

        it "does not label the PR" do
          creator.create

          expect(WebMock).
            to_not have_requested(
              :post,
              "#{watched_repo_url}/issues/1347/labels"
            )
        end
      end
    end
  end
end
