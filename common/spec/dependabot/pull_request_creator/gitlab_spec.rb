# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/gitlab"

RSpec.describe Dependabot::PullRequestCreator::Gitlab do
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
      labeler: labeler,
      approvers: approvers,
      assignees: assignees,
      milestone: milestone,
      target_project_id: target_project_id
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
  end
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }
  let(:base_commit) { "basecommitsha" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "gitlab.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [gemfile, gemfile_lock, created_file, deleted_file] }
  let(:commit_message) { "Commit msg" }
  let(:pr_description) { "PR msg" }
  let(:pr_name) { "PR name" }
  let(:author_details) { nil }
  let(:approvers) { nil }
  let(:assignees) { nil }
  let(:milestone) { nil }
  let(:target_project_id) { nil }
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
  let(:created_file) do
    Dependabot::DependencyFile.new(
      name: "created-file",
      content: "created",
      operation: Dependabot::DependencyFile::Operation::CREATE
    )
  end
  let(:deleted_file) do
    Dependabot::DependencyFile.new(
      name: "deleted-file",
      content: nil,
      operation: Dependabot::DependencyFile::Operation::DELETE
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:repo_api_url) do
    "https://gitlab.com/api/v4/projects/#{CGI.escape(source.repo)}"
  end

  before do
    stub_request(:get, repo_api_url)
      .to_return(status: 200,
                 body: fixture("gitlab", "bump_repo.json"),
                 headers: json_header)
    stub_request(
      :get,
      "#{repo_api_url}/repository/branches/#{CGI.escape(branch_name)}"
    ).to_return(
      status: 404,
      body: fixture("gitlab", "branch_not_found.json"),
      headers: json_header
    )
    stub_request(:post, "#{repo_api_url}/repository/branches")
      .with(query: { branch: branch_name, ref: base_commit })
      .to_return(status: 200,
                 body: fixture("gitlab", "branch.json"),
                 headers: json_header)
    stub_request(:post, "#{repo_api_url}/repository/commits")
      .to_return(status: 200,
                 body: fixture("gitlab", "create_commit.json"),
                 headers: json_header)
    stub_request(:get, "#{repo_api_url}/labels?per_page=100")
      .to_return(status: 200,
                 body: fixture("gitlab", "labels_with_dependencies.json"),
                 headers: json_header)
    stub_request(:post, "#{repo_api_url}/merge_requests")
      .to_return(status: 200,
                 body: fixture("gitlab", "merge_request.json"),
                 headers: json_header)
  end

  describe "#create" do
    it "pushes a commit to GitLab and creates a merge request" do
      creator.create

      expect(WebMock)
        .to have_requested(:post, "#{repo_api_url}/repository/commits")
        .with(
          body: {
            branch: branch_name,
            commit_message: commit_message,
            actions: [
              {
                action: "update",
                file_path: gemfile.path,
                content: gemfile.content,
                encoding: "text"
              },
              {
                action: "update",
                file_path: gemfile_lock.path,
                content: gemfile_lock.content,
                encoding: "text"
              },
              {
                action: "create",
                file_path: created_file.path,
                content: created_file.content,
                encoding: "text"
              },
              {
                action: "delete",
                file_path: deleted_file.path,
                content: "",
                encoding: "text"
              }
            ]
          }
        )

      expect(WebMock)
        .to have_requested(:post, "#{repo_api_url}/merge_requests")
    end

    context "with reviewers" do
      let(:approvers) { { reviewers: [1_394_555] } }

      it "pushes a commit to GitLab and creates a merge request with assigned reviewers" do
        creator.create

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/merge_requests")
          .with(
            body: a_string_including("reviewer_ids%5B%5D=#{approvers[:reviewers].first}")
          )
      end
    end

    context "with forked project" do
      let(:target_project_id) { 1 }

      it "pushes a commit to GitLab and creates a merge request in upstream project" do
        creator.create

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/merge_requests")
          .with(
            body: a_string_including("target_project_id=#{target_project_id}")
          )
      end
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

      before do
        stub_request(:put, "#{repo_api_url}/repository/submodules/manifesto")
          .to_return(status: 200,
                     body: fixture("gitlab", "create_commit.json"),
                     headers: json_header)
      end

      it "pushes a commit to GitLab and creates a merge request" do
        creator.create

        expect(WebMock)
          .to have_requested(
            :put, "#{repo_api_url}/repository/submodules/manifesto"
          ).with(
            body: hash_including(
              branch: branch_name,
              commit_sha: "sha1",
              commit_message: commit_message
            )
          )
        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/merge_requests")
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

      it "pushes a commit to GitLab and creates a merge request" do
        creator.create

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/repository/commits")
          .with(
            body: {
              branch: branch_name,
              commit_message: commit_message,
              actions: [
                {
                  action: "update",
                  file_path: files[0].directory + "/" + files[0].name,
                  content: files[0].content,
                  encoding: "base64"
                }
              ]
            }
          )

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/merge_requests")
      end

      context "with author details" do
        let(:author_details) do
          {
            email: "no-reply@example.com",
            name: "Dependabot"
          }
        end

        it "pushes a commit to GitLab and creates and set the proper author details" do
          creator.create

          expect(WebMock)
            .to have_requested(:post, "#{repo_api_url}/repository/commits")
            .with(
              body: {
                branch: branch_name,
                commit_message: commit_message,
                actions: [
                  {
                    action: "update",
                    file_path: files[0].directory + "/" + files[0].name,
                    content: files[0].content,
                    encoding: "base64"
                  }
                ],
                author_email: "no-reply@example.com",
                author_name: "Dependabot"
              }
            )

          expect(WebMock)
            .to have_requested(:post, "#{repo_api_url}/merge_requests")
        end
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

      it "pushes a commit to GitLab and creates a merge request" do
        creator.create

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/repository/commits")
          .with(
            body: {
              branch: branch_name,
              commit_message: commit_message,
              actions: [
                {
                  action: "update",
                  file_path: files[0].symlink_target,
                  content: files[0].content,
                  encoding: "text"
                }
              ]
            }
          )

        expect(WebMock)
          .to have_requested(:post, "#{repo_api_url}/merge_requests")
      end
    end

    context "when the branch already exists" do
      before do
        stub_request(
          :get,
          "#{repo_api_url}/repository/branches/#{CGI.escape(branch_name)}"
        ).to_return(
          status: 200,
          body: fixture("gitlab", "branch.json"),
          headers: json_header
        )
      end

      context "when a merge request to this branch doesn't exist" do
        before do
          stub_request(:get, "#{repo_api_url}/merge_requests")
            .with(
              query: {
                source_branch: branch_name,
                target_branch: "master",
                state: "all"
              }
            ).to_return(status: 200, body: "[]", headers: json_header)
        end

        context "when the commit doesn't already exists on that branch" do
          before do
            stub_request(:get, "#{repo_api_url}/repository/commits")
              .with(query: { ref_name: branch_name })
              .to_return(status: 200,
                         body: fixture("gitlab", "commits.json"),
                         headers: json_header)
          end

          it "creates a commit and merge request with the right details" do
            expect(creator.create).not_to be_nil

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/repository/commits")
            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/merge_requests")
          end
        end

        context "when a commit already exists on that branch" do
          before do
            stub_request(:get, "#{repo_api_url}/repository/commits")
              .with(query: { ref_name: branch_name })
              .to_return(status: 200,
                         body: fixture("gitlab", "commits_with_existing.json"),
                         headers: json_header)
          end

          it "creates a merge request but not a commit" do
            expect(creator.create).not_to be_nil

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/repository/commits")
            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/merge_requests")
          end
        end
      end

      context "when a merge request to this branch already exists" do
        before do
          stub_request(:get, "#{repo_api_url}/merge_requests")
            .with(
              query: {
                source_branch: branch_name,
                target_branch: "master",
                state: "all"
              }
            ).to_return(status: 200, body: "[{}]", headers: json_header)
        end

        it "doesn't create a commit or merge request (and returns nil)" do
          expect(creator.create).to be_nil

          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/repository/commits")
          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/merge_requests")
        end
      end
    end

    context "when a approvers has been requested" do
      let(:approvers) { { approvers: [1_394_555] } }
      let(:mr_api_url) do
        "https://gitlab.com/api/v4/projects/#{target_project_id || CGI.escape(source.repo)}/merge_requests"
      end

      before do
        stub_request(:post, "#{mr_api_url}/5/approval_rules")
          .to_return(
            status: 200,
            body: fixture("gitlab", "merge_request.json"),
            headers: json_header
          )
      end

      it "adds the approvers to the MR correctly" do
        creator.create

        expect(WebMock)
          .to have_requested(:post, "#{mr_api_url}/5/approval_rules")
          .with(body: {
            name: "dependency-updates",
            approvals_required: 1,
            user_ids: approvers[:approvers],
            group_ids: ""
          })
      end

      context "with forked project" do
        let(:target_project_id) { 1 }

        it "adds the approvers to upstream project MR" do
          creator.create

          expect(WebMock)
            .to have_requested(:post, "#{mr_api_url}/5/approval_rules")
            .with(body: {
              name: "dependency-updates",
              approvals_required: 1,
              user_ids: approvers[:approvers],
              group_ids: ""
            })
        end
      end
    end
  end
end
