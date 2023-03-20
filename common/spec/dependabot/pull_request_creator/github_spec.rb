# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/github"

RSpec.describe Dependabot::PullRequestCreator::Github do
  subject(:creator) do
    described_class.new(
      source: source,
      branch_name: branch_name,
      base_commit: base_commit,
      credentials: credentials,
      files: files,
      commit_message: commit_message,
      pr_description: pr_description,
      pr_name: pr_name,
      author_details: author_details,
      signature_key: signature_key,
      custom_headers: custom_headers,
      labeler: labeler,
      reviewers: reviewers,
      assignees: assignees,
      milestone: milestone,
      require_up_to_date_base: require_up_to_date_base
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }
  let(:base_commit) { "basecommitsha" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:commit_message) { "Commit msg" }
  let(:pr_description) { "PR msg" }
  let(:pr_name) { "PR name" }
  let(:author_details) { nil }
  let(:signature_key) { nil }
  let(:custom_headers) { nil }
  let(:reviewers) { nil }
  let(:assignees) { nil }
  let(:milestone) { nil }
  let(:require_up_to_date_base) { false }
  let(:labeler) do
    Dependabot::PullRequestCreator::Labeler.new(
      source: source,
      credentials: credentials,
      custom_labels: custom_labels,
      includes_security_fixes: false,
      dependencies: [dependency],
      label_language: false,
      automerge_candidate: false
    )
  end
  let(:custom_labels) { nil }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [],
      previous_requirements: []
    )
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }
  let(:service_pack_response) { fixture("git", "upload_packs", "business") }

  before do
    stub_request(:get, repo_api_url).
      to_return(status: 200,
                body: fixture("github", "bump_repo.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/git/trees").
      to_return(status: 200,
                body: fixture("github", "create_tree.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/git/commits").
      to_return(status: 200,
                body: fixture("github", "create_commit.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/git/refs").
      to_return(status: 200,
                body: fixture("github", "create_ref.json"),
                headers: json_header)
    stub_request(:get, "#{repo_api_url}/labels?per_page=100").
      to_return(status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/pulls").
      to_return(status: 200,
                body: fixture("github", "create_pr.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/issues/1347/labels").
      to_return(status: 200,
                body: fixture("github", "create_label.json"),
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/git/blobs").
      to_return(status: 200,
                body: fixture("github", "create_blob.json"),
                headers: json_header)

    service_pack_url =
      "https://github.com/gocardless/bump.git/info/refs" \
      "?service=git-upload-pack"
    stub_request(:get, service_pack_url).
      to_return(
        status: 200,
        body: service_pack_response,
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  describe "#create" do
    it "pushes a commit to GitHub" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/git/trees").
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
              content: fixture("ruby", "gemfiles", "Gemfile")
            }
          ]
        })

      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/git/commits").
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
          to have_requested(:post, "#{repo_api_url}/git/trees").
          with(body: {
            base_tree: "basecommitsha",
            tree: [{
              path: "manifesto",
              mode: "160000",
              type: "commit",
              sha: "sha1"
            }]
          })

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/commits")
      end
    end

    context "with a symlink" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "manifesto",
            type: "symlink",
            content: "codes",
            symlink_target: "nested/manifesto"
          )
        ]
      end

      it "pushes a commit to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/trees").
          with(body: {
            base_tree: "basecommitsha",
            tree: [{
              path: "nested/manifesto",
              mode: "100644",
              type: "blob",
              content: "codes"
            }]
          })

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/commits")
      end
    end

    context "with a binary file" do
      let(:gem_content) do
        Base64.encode64(fixture("ruby", "gems", "addressable-2.7.0.gem"))
      end

      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "addressable-2.7.0.gem",
            directory: "vendor/cache",
            content: gem_content,
            content_encoding:
              Dependabot::DependencyFile::ContentEncoding::BASE64
          )
        ]
      end
      let(:sha) { "3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15" }

      it "creates a git blob and pushes a commit to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/blobs").
          with(body: {
            content: gem_content,
            encoding: "base64"
          })

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/trees").
          with(body: {
            base_tree: "basecommitsha",
            tree: [{
              path: "vendor/cache/addressable-2.7.0.gem",
              mode: "100644",
              type: "blob",
              sha: sha
            }]
          })

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/commits")
      end
    end

    context "with a deleted file" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "addressable-2.7.0.gem",
            directory: "vendor/cache",
            content: nil,
            operation: Dependabot::DependencyFile::Operation::DELETE,
            content_encoding:
              Dependabot::DependencyFile::ContentEncoding::BASE64
          )
        ]
      end

      it "pushes a commit to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/trees").
          with(body: {
            base_tree: "basecommitsha",
            tree: [{
              path: "vendor/cache/addressable-2.7.0.gem",
              mode: "100644",
              type: "blob",
              sha: nil
            }]
          })

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/commits")
      end
    end

    context "when the repo doesn't exist" do
      before do
        stub_request(:get, repo_api_url).
          to_return(status: 404,
                    body: fixture("github", "not_found.json"),
                    headers: json_header)
        stub_request(:post, "#{repo_api_url}/git/trees").
          to_return(status: 404,
                    body: fixture("github", "not_found.json"),
                    headers: json_header)

        service_pack_url =
          "https://github.com/gocardless/bump.git/info/refs" \
          "?service=git-upload-pack"
        stub_request(:get, service_pack_url).to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { creator.create }.
          to raise_error(Dependabot::PullRequestCreator::RepoNotFound)
      end
    end

    context "when we got a 401" do
      before do
        url = "https://github.com/gocardless/bump.git"
        service_pack_url = "#{url}/info/refs?service=git-upload-pack"

        stub_request(:get, service_pack_url).to_return(status: 401)

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it "raises a normal error" do
        expect { creator.create }.to raise_error(Octokit::Unauthorized)
      end
    end

    context "when the repo exists but we got a 404" do
      before do
        stub_request(:get, repo_api_url).
          to_return(status: 200,
                    body: fixture("github", "bump_repo.json"),
                    headers: json_header)

        url = "https://github.com/gocardless/bump.git"
        service_pack_url = "#{url}/info/refs?service=git-upload-pack"

        stub_request(:get, service_pack_url).to_return(status: 404)

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it "raises a normal error" do
        expect { creator.create }.to raise_error(/Unexpected git error!/)
      end
    end

    context "when the repo exists but is disabled" do
      before do
        url = "https://github.com/gocardless/bump.git"
        service_pack_url = "#{url}/info/refs?service=git-upload-pack"

        stub_request(:get, service_pack_url).
          to_return(
            status: 403,
            body: "Account `gocardless' is disabled. Please ask the owner to " \
                  "check their account."
          )

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it "raises a helpful error" do
        expect { creator.create }.
          to raise_error(Dependabot::PullRequestCreator::RepoDisabled)
      end
    end

    context "when creating the branch fails" do
      before do
        stub_request(:post, "#{repo_api_url}/git/refs").
          to_return(status: 422,
                    body: fixture("github", "create_ref_unhandled_error.json"),
                    headers: json_header)
      end

      it "raises a normal error" do
        expect { creator.create }.to raise_error(Octokit::UnprocessableEntity)
      end

      context "because the branch is a superstring of another branch" do
        before do
          allow(SecureRandom).to receive(:hex).and_return("rand")

          stub_request(:post, "#{repo_api_url}/git/refs").
            with(
              body: {
                ref: "refs/heads/rand#{branch_name}",
                sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
              }.to_json
            ).
            to_return(status: 200,
                      body: fixture("github", "create_ref.json"),
                      headers: json_header)
        end

        it "creates a PR with the right details" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/pulls").
            with(
              body: {
                base: "master",
                head: "randdependabot/bundler/business-1.5.0",
                title: "PR name",
                body: "PR msg"
              }
            )
        end

        context "with a custom header" do
          let(:custom_headers) { { "Accept" => "some-preview-header" } }

          it "creates a PR with the right details" do
            creator.create

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/pulls").
              with(
                body: {
                  base: "master",
                  head: "randdependabot/bundler/business-1.5.0",
                  title: "PR name",
                  body: "PR msg"
                },
                headers: { "Accept" => "some-preview-header" }
              )
          end
        end
      end
    end

    context "when the branch already exists" do
      before do
        service_pack_response.gsub!("heads/rubocop", "heads/#{branch_name}")
      end

      context "but a PR to this branch doesn't" do
        before do
          url = "#{repo_api_url}/pulls?head=gocardless:#{branch_name}" \
                "&state=all"
          stub_request(:get, url).
            to_return(status: 200, body: "[]", headers: json_header)
          stub_request(
            :patch,
            "#{repo_api_url}/git/refs/heads/#{branch_name}"
          ).to_return(
            status: 200,
            body: fixture("github", "update_ref.json"),
            headers: json_header
          )
        end

        it "creates a PR with the right details" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/pulls").
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
          url = "#{repo_api_url}/pulls?head=gocardless:#{branch_name}" \
                "&state=all"
          stub_request(:get, url).
            to_return(status: 200, body: "[{}]", headers: json_header)
        end

        it "returns nil" do
          expect(creator.create).to be_nil
          expect(WebMock).to_not have_requested(:post, "#{repo_api_url}/pulls")
        end

        context "but isn't initially returned (a race)" do
          before do
            url = "#{repo_api_url}/pulls?head=gocardless:#{branch_name}" \
                  "&state=all"
            stub_request(:get, url).
              to_return(status: 200, body: "[]", headers: json_header)
            stub_request(
              :patch,
              "#{repo_api_url}/git/refs/heads/#{branch_name}"
            ).to_return(
              status: 200,
              body: fixture("github", "update_ref.json"),
              headers: json_header
            )
            stub_request(:post, "#{repo_api_url}/pulls").
              to_return(
                status: 422,
                body: fixture("github", "pull_request_already_exists.json"),
                headers: json_header
              )
          end

          it "returns nil" do
            expect(creator.create).to be_nil
            expect(WebMock).to have_requested(:post, "#{repo_api_url}/pulls")
          end
        end

        context "but is merged" do
          before do
            url = "#{repo_api_url}/pulls?head=gocardless:#{branch_name}" \
                  "&state=all"
            stub_request(:get, url).to_return(
              status: 200,
              body: "[{ \"merged\": true }]",
              headers: json_header
            )
            stub_request(
              :patch,
              "#{repo_api_url}/git/refs/heads/#{branch_name}"
            ).to_return(
              status: 200,
              body: fixture("github", "update_ref.json"),
              headers: json_header
            )
          end
          let(:base_commit) { "basecommitsha" }

          it "creates a PR" do
            creator.create

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/pulls").
              with(
                body: {
                  base: "master",
                  head: "dependabot/bundler/business-1.5.0",
                  title: "PR name",
                  body: "PR msg"
                }
              )
          end

          context "when `require_up_to_date_base` is true" do
            let(:require_up_to_date_base) { true }

            it "does not create a PR" do
              expect(creator.create).to be_nil
              expect(WebMock).
                to_not have_requested(:post, "#{repo_api_url}/pulls")
            end

            context "and the commit we're branching off of is up-to-date" do
              let(:base_commit) { "7bb4e41ce5164074a0920d5b5770d196b4d90104" }

              it "creates a PR" do
                creator.create

                expect(WebMock).
                  to have_requested(:post, "#{repo_api_url}/pulls").
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
          end
        end
      end
    end

    context "when the PR doesn't have history in common with the base branch" do
      before do
        stub_request(:post, "#{repo_api_url}/pulls").
          to_return(status: 422,
                    body: { message: "has no history in common" }.to_json,
                    headers: json_header)
      end

      it "raises a helpful error" do
        expect { creator.create }.
          to raise_error(Dependabot::PullRequestCreator::NoHistoryInCommon)
      end
    end

    context "when a branch with a name that is a superstring exists" do
      before do
        service_pack_response.gsub!("heads/rubocop", "heads/#{branch_name}.1")
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/pulls").
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
      let(:author_details) do
        { email: "support@dependabot.com", name: "dependabot" }
      end

      it "passes the author details to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/git/commits").
          with(body: {
            parents: anything,
            tree: anything,
            message: anything,
            author: { email: "support@dependabot.com", name: "dependabot" }
          })
      end

      context "with a signature key" do
        let(:signature_key) { fixture("keys", "pgp.key") }
        let(:public_key) { fixture("keys", "pgp.pub") }
        let(:text_to_sign) do
          "tree cd8274d15fa3ae2ab983129fb037999f264ba9a7\n" \
            "parent basecommitsha\n" \
            "author dependabot <support@dependabot.com> 978307200 +0000\n" \
            "committer dependabot <support@dependabot.com> 978307200 +0000\n" \
            "\n" \
            "Commit msg"
        end
        before { allow(Time).to receive(:now).and_return(Time.new(2001, 1, 1, 0, 0, 0, "+00:00")) }

        it "passes the author details and signature to GitHub" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/git/commits").
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
            have_requested(:post, "#{repo_api_url}/git/commits").
              with do |req|
                signature = JSON.parse(req.body)["signature"]
                valid_sig = false

                dir = Dir.mktmpdir
                begin
                  GPGME::Engine.home_dir = dir
                  GPGME::Key.import(public_key)

                  crypto = GPGME::Crypto.new(armor: true)
                  crypto.verify(signature, signed_text: text_to_sign) do |sig|
                    valid_sig = sig.valid?
                  end
                ensure
                  FileUtils.remove_entry(dir, true)
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
        to have_requested(:post, "#{repo_api_url}/git/refs").
        with(body: {
          ref: "refs/heads/dependabot/bundler/business-1.5.0",
          sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
        })
    end

    it "creates a PR with the right details" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/pulls").
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
        to have_requested(:post, "#{repo_api_url}/issues/1347/labels").
        with(body: '["dependencies"]')
    end

    it "returns details of the created pull request" do
      expect(creator.create.title).to eq("new-feature")
      expect(creator.create.number).to eq(1347)
    end

    context "with a target branch" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          branch: "my_branch"
        )
      end
      let(:branch_name) { "dependabot/bundler/my_branch/business-1.5.0" }

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/pulls").
          with(
            body: {
              base: "my_branch",
              head: "dependabot/bundler/my_branch/business-1.5.0",
              title: "PR name",
              body: "PR msg"
            }
          )
      end

      context "that doesn't exist" do
        before do
          stub_request(:post, "#{repo_api_url}/pulls").
            to_return(status: 422,
                      body: fixture("github", "invalid_base_branch.json"),
                      headers: json_header)
        end

        it "quietly ignores the failure" do
          expect { creator.create }.to_not raise_error
        end
      end
    end

    context "when the 'dependencies' label doesn't yet exist" do
      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_without_dependencies.json"),
                    headers: json_header)
        stub_request(:post, "#{repo_api_url}/labels").
          to_return(status: 201,
                    body: fixture("github", "create_label.json"),
                    headers: json_header)
      end

      it "creates a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/labels").
          with(
            body: {
              name: "dependencies",
              color: "0366d6",
              description: "Pull requests that update a dependency file"
            }
          )
      end

      context "when there's a race and we lose" do
        before do
          stub_request(:post, "#{repo_api_url}/labels").
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
        stub_request(:get, "#{repo_api_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_with_custom.json"),
                    headers: json_header)
      end

      it "does not create a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to_not have_requested(:post, "#{repo_api_url}/labels")
      end

      it "labels the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/issues/1347/labels").
          with(body: '["Dependency: Gems"]')
      end
    end

    context "when a custom dependencies label has been requested" do
      let(:custom_labels) { ["wontfix"] }

      it "does not create a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to_not have_requested(:post, "#{repo_api_url}/labels")
      end

      it "labels the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/issues/1347/labels").
          with(body: '["wontfix"]')
      end

      context "that doesn't exist" do
        let(:custom_labels) { ["non-existent"] }

        # Alternatively we could create the label (current choice isn't fixed)
        it "does not create any labels" do
          creator.create

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/labels")
        end

        it "does not label the PR" do
          creator.create

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/issues/1347/labels")
        end
      end

      context "with multiple custom labels and one removed" do
        let(:custom_labels) { %w(wontfix non-existent) }

        it "labels the PR with the label that does exist" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/issues/1347/labels").
            with(body: '["wontfix"]')
        end
      end
    end

    context "when a reviewer has been requested" do
      let(:reviewers) { { "reviewers" => ["greysteil"] } }
      before do
        stub_request(:post, "#{repo_api_url}/pulls/1347/requested_reviewers").
          to_return(status: 200,
                    body: fixture("github", "create_pr.json"),
                    headers: json_header)
      end

      it "adds the reviewer to the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(
            :post, "#{repo_api_url}/pulls/1347/requested_reviewers"
          ).with(body: { reviewers: ["greysteil"], team_reviewers: [] }.to_json)
      end

      context "that can't be added" do
        before do
          stub_request(:post, "#{repo_api_url}/pulls/1347/requested_reviewers").
            to_return(status: 422,
                      body: fixture("github", "add_reviewer_error.json"),
                      headers: json_header)
          stub_request(:post, "#{repo_api_url}/issues/1347/comments")
        end
        let(:expected_comment_body) do
          "Dependabot tried to add `@greysteil` as a reviewer to this PR, " \
            "but received the following error from GitHub:\n\n" \
            "```\n" \
            "POST https://api.github.com/repos/gocardless/bump/pulls" \
            "/1347/requested_reviewers: 422 - Reviews may only be requested " \
            "from collaborators. One or more of the users or teams you " \
            "specified is not a collaborator of the example/repo repository. " \
            "// See: https://developer.github.com/v3/pulls/review_requests/" \
            "#create-a-review-request\n" \
            "```"
        end

        it "comments on the PR with details of the failure" do
          creator.create

          expect(WebMock).to have_requested(
            :post,
            "#{repo_api_url}/pulls/1347/requested_reviewers"
          )
          expect(WebMock).to have_requested(
            :post,
            "#{repo_api_url}/issues/1347/comments"
          ).with(body: { body: expected_comment_body }.to_json)
        end
      end
    end

    context "when an assignee has been requested" do
      let(:assignees) { ["greysteil"] }
      before do
        stub_request(:post, "#{repo_api_url}/issues/1347/assignees").
          to_return(status: 201,
                    body: fixture("github", "create_pr.json"),
                    headers: json_header)
      end

      it "adds the assignee to the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{repo_api_url}/issues/1347/assignees").
          with(body: { assignees: ["greysteil"] }.to_json)
      end

      context "and GitHub 404s" do
        before do
          stub_request(:post, "#{repo_api_url}/issues/1347/assignees").
            to_return(status: 404)
        end

        it "quietly ignores the 404" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/issues/1347/assignees").
            with(body: { assignees: ["greysteil"] }.to_json)
        end
      end
    end

    context "when a milestone has been requested" do
      let(:milestone) { 5 }
      before do
        stub_request(:patch, "#{repo_api_url}/issues/1347").
          to_return(status: 201,
                    body: fixture("github", "create_pr.json"),
                    headers: json_header)
      end

      it "adds the milestone to the PR correctly" do
        creator.create

        expect(WebMock).
          to have_requested(
            :patch, "#{repo_api_url}/issues/1347"
          ).with(body: { milestone: 5 }.to_json)
      end

      context "but can't be specified for some reason" do
        before do
          stub_request(:patch, "#{repo_api_url}/issues/1347").
            to_return(status: 422,
                      body: fixture("github", "milestone_invalid.json"),
                      headers: json_header)
        end

        it "quietly ignores the error" do
          expect(creator.create.title).to eq("new-feature")
        end
      end
    end

    context "when labelling fails" do
      context "with internal server error" do
        before do
          stub_request(:post, "#{repo_api_url}/issues/1347/labels").
            to_return(status: 500,
                      body: "{}",
                      headers: json_header)
        end

        it "raises helpful error" do
          msg = "POST https://api.github.com/repos/gocardless/bump/issues/" \
                "1347/labels: 500 - "
          expect { creator.create }.to raise_error(
            (an_instance_of(Dependabot::PullRequestCreator::AnnotationError).
              and having_attributes(message: msg).
              and having_attributes(
                cause: an_instance_of(Octokit::InternalServerError)
              ).
              and having_attributes(
                pull_request: having_attributes(number: 1347)
              )
            )
          )
        end
      end

      context "with disabled account error" do
        before do
          stub_request(:post, "#{repo_api_url}/issues/1347/labels").
            to_return(status: 403,
                      body: '{"error":"Account `gocardless\' is disabled. ' \
                            'Please ask the owner to check their account."}',
                      headers: json_header)
        end

        it "raises helpful error" do
          msg = "POST https://api.github.com/repos/gocardless/bump/issues/" \
                "1347/labels: 403 - Error: Account `gocardless' is disabled. " \
                "Please ask the owner to check their account."
          expect { creator.create }.to raise_error(
            (an_instance_of(Dependabot::PullRequestCreator::AnnotationError).
              and having_attributes(message: msg).
              and having_attributes(
                cause: an_instance_of(
                  Dependabot::PullRequestCreator::RepoDisabled
                )
              ).
              and having_attributes(
                pull_request: having_attributes(number: 1347)
              )
            )
          )
        end
      end

      context "the PR description is too long" do
        let(:pr_description) { "a" * (described_class::MAX_PR_DESCRIPTION_LENGTH + 1) }

        it "truncates the description" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/pulls").
            with(
              body: {
                base: "master",
                head: "dependabot/bundler/business-1.5.0",
                title: "PR name",
                body: ->(body) { expect(body.length).to be <= described_class::MAX_PR_DESCRIPTION_LENGTH }
              }
            )
        end
      end
    end
  end
end
