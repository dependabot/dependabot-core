# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_updater/gitlab"

RSpec.describe Dependabot::PullRequestUpdater::Gitlab do
  subject(:updater) do
    described_class.new(
      source: source,
      base_commit: base_commit,
      old_commit: old_commit,
      files: files,
      credentials: credentials,
      pull_request_number: merge_request_number,
      target_project_id: target_project_id
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
  end
  let(:files) { [gemfile, gemfile_lock, created_file, created_executable, deleted_file] }
  let(:base_commit) { "basecommitsha" }
  let(:old_commit) { "oldcommitsha" }
  let(:merge_request_number) do
    JSON.parse(fixture("gitlab", "merge_request.json"))["iid"]
  end
  let(:branch_name) { JSON.parse(fixture("gitlab", "branch.json"))["name"] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "gitlab.com",
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
      content: fixture("ruby", "gemfiles", "Gemfile"),
      directory: "files/are/here"
    )
  end
  let(:created_file) do
    Dependabot::DependencyFile.new(
      name: "created-file",
      content: "created",
      operation: Dependabot::DependencyFile::Operation::CREATE
    )
  end
  let(:created_executable) do
    Dependabot::DependencyFile.new(
      name: "created-executable-file",
      content: "created-executable",
      operation: Dependabot::DependencyFile::Operation::CREATE,
      execute_filemode: true
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
  let(:merge_request_url) do
    repo_api_url + "/merge_requests/#{merge_request_number}"
  end
  let(:branch_url) do
    repo_api_url + "/repository/branches/" + CGI.escape(branch_name)
  end
  let(:commit_url) { repo_api_url + "/repository/commits" }
  let(:target_project_id) { nil }

  before do
    stub_request(:get, merge_request_url).
      to_return(status: 200,
                body: fixture("gitlab", "merge_request.json"),
                headers: json_header)
    stub_request(:get, branch_url).
      to_return(status: 200,
                body: fixture("gitlab", "branch.json"),
                headers: json_header)
    stub_request(:post, commit_url).
      to_return(status: 200,
                body: fixture("gitlab", "create_commit.json"),
                headers: json_header)
    stub_request(:get, commit_url + "/#{old_commit}").
      to_return(status: 200,
                body: fixture("gitlab", "create_commit.json"),
                headers: json_header)
  end

  describe "#update" do
    context "with forked project" do
      let(:target_project_id) { 1 }
      let(:merge_request_url) do
        "https://gitlab.com/api/v4/projects/#{target_project_id}/merge_requests/#{merge_request_number}"
      end

      it "fetches mr from upstream project" do
        updater.update

        expect(WebMock).
          to have_requested(:get, merge_request_url)
      end
    end

    context "when the branch doesn't exist" do
      before { stub_request(:get, branch_url).to_return(status: 404) }

      it "doesn't push a commit to Gitlab" do
        updater.update
        expect(WebMock).
          to_not have_requested(:post, commit_url)
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end

    context "when the merge request doesn't exist" do
      before { stub_request(:get, merge_request_url).to_return(status: 404) }

      it "doesn't push a commit to Gitlab" do
        updater.update
        expect(WebMock).
          to_not have_requested(:post, commit_url)
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end

    it "pushes a commit to Gitlab" do
      updater.update

      expect(WebMock).
        to have_requested(:post, commit_url).
        with(
          body: {
            branch: branch_name,
            commit_message: JSON.parse(
              fixture("gitlab", "create_commit.json")
            )["title"],
            actions: [
              {
                action: "update",
                file_path: gemfile.path,
                content: gemfile.content
              },
              {
                action: "update",
                file_path: gemfile_lock.path,
                content: gemfile_lock.content
              },
              {
                action: "create",
                file_path: created_file.path,
                content: created_file.content
              },
              {
                action: "create",
                file_path: created_executable.path,
                content: created_executable.content
              },
              {
                action: "delete",
                file_path: deleted_file.path,
                content: ""
              },
              {
                action: "chmod",
                file_path: created_executable.path,
                execute_filemode: true
              }
            ],
            force: true,
            start_branch: JSON.parse(
              fixture("gitlab", "merge_request.json")
            )["target_branch"]
          }
        )
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

      it "pushes a commit to Gitlab" do
        updater.update

        expect(WebMock).
          to have_requested(:post, commit_url).
          with(
            body: {
              branch: branch_name,
              commit_message: JSON.parse(
                fixture("gitlab", "create_commit.json")
              )["title"],
              actions: [
                {
                  action: "update",
                  file_path: files[0].symlink_target,
                  content: files[0].content
                }
              ],
              force: true,
              start_branch: JSON.parse(
                fixture("gitlab", "merge_request.json")
              )["target_branch"]
            }
          )
      end
    end
  end
end
