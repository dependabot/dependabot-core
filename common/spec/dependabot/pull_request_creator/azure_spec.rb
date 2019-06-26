# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/azure"

RSpec.describe Dependabot::PullRequestCreator::Azure do
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
      labeler: labeler
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "azure", repo: "org/gocardless/_git/bump")
  end
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }
  let(:base_commit) { "basecommitsha" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "dev.azure.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:commit_message) { "Commit msg" }
  let(:pr_description) { "PR msg" }
  let(:pr_name) { "PR name" }
  let(:author_details) { nil }
  let(:approvers) { nil }
  let(:assignee) { nil }
  let(:milestone) { nil }
  let(:dep_source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:labeler) do
    Dependabot::PullRequestCreator::Labeler.new(
      source: dep_source,
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
  let(:repo_api_url) do
    "https://dev.azure.com/org/gocardless/_apis/git/repositories/bump"
  end

  before do
    stub_request(:get, repo_api_url).
      to_return(status: 200,
                body: fixture("azure", "bump_repo.json"),
                headers: json_header)
    stub_request(
      :get,
      "#{repo_api_url}/refs?filter=heads/#{CGI.escape(branch_name)}"
    ).to_return(
      status: 200,
      body: fixture("azure", "branch_not_found.json"),
      headers: json_header
    )
    stub_request(:post, "#{repo_api_url}/pushes?api-version=5.0").
      to_return(status: 200,
                headers: json_header)
    stub_request(:post, "#{repo_api_url}/pullrequests?api-version=5.0").
      to_return(status: 200,
                headers: json_header)

    # dependency lookups
    stub_request(
      :get,
      "https://api.github.com/repos/gocardless/bump/labels?per_page=100"
    ).to_return(status: 200,
                body: fixture("gitlab", "labels_with_dependencies.json"),
                headers: json_header)
  end

  describe "#create" do
    it "pushes a commit to GitLab and creates a pull request" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/pushes?api-version=5.0")
      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/pullrequests?api-version=5.0")
    end

    context "when the branch already exists" do
      before do
        stub_request(
          :get,
          "#{repo_api_url}/refs?filter=heads/#{CGI.escape(branch_name)}"
        ).to_return(
          status: 200,
          body: fixture("azure", "default_branch.json"),
          headers: json_header
        )
      end

      context "but a pull request to this branch doesn't" do
        before do
          stub_request(
            :get,
            "#{repo_api_url}/pullrequests?" \
              "searchCriteria.sourceRefName=refs/heads/" + branch_name +
              "&searchCriteria.status=all" \
              "&searchCriteria.targetRefName=refs/heads/master"
          ).to_return(
            status: 200,
            body: fixture("azure", "branch_not_found.json"),
            headers: json_header
          )
        end

        context "and the commit doesn't already exists on that branch" do
          before do
            stub_request(
              :get,
              "#{repo_api_url}/commits?" \
                "searchCriteria.itemVersion.version=" + branch_name
            ).to_return(status: 200,
                        body: fixture("azure", "commits_with_existing.json"),
                        headers: json_header)
          end

          it "creates a commit and pull request with the right details" do
            expect(creator.create).to_not be_nil

            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pushes?api-version=5.0"
              )
            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pullrequests?api-version=5.0"
              )
          end
        end

        context "and a commit already exists on that branch" do
          before do
            stub_request(
              :get,
              "#{repo_api_url}/commits?" \
                "searchCriteria.itemVersion.version=" + branch_name
            ).to_return(
              status: 200,
              body: fixture("azure", "commits_with_existing.json"),
              headers: json_header
            )
          end

          it "creates a pull request but not a commit" do
            expect(creator.create).to_not be_nil

            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pushes?api-version=5.0"
              )
            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pullrequests?api-version=5.0"
              )
          end
        end
      end

      context "and a pull request to this branch already exists" do
        before do
          stub_request(
            :get,
            "#{repo_api_url}/commits?" \
              "searchCriteria.itemVersion.version=" + branch_name
          ).to_return(status: 200,
                      body: fixture("azure", "commits_with_existing.json"),
                      headers: json_header)

          stub_request(
            :get,
            "#{repo_api_url}/pullrequests?searchCriteria.status=all" \
              "&searchCriteria.sourceRefName=refs/heads/" + branch_name +
              "&searchCriteria.targetRefName=refs/heads/master"
          ).to_return(
            status: 200,
            body: fixture("azure", "pull_request.json"),
            headers: json_header
          )
        end

        it "doesn't create a commit or pull request (and returns nil)" do
          expect(creator.create).to be_nil

          expect(WebMock).
            to_not have_requested(
              :post,
              "#{repo_api_url}/pushes?api-version=5.0"
            )
          expect(WebMock).
            to_not have_requested(
              :post,
              "#{repo_api_url}/pullrequests?api-version=5.0"
            )
        end
      end
    end
  end
end
