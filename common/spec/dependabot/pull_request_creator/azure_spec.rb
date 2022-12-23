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
      author_details: author_details,
      labeler: labeler,
      reviewers: reviewers,
      assignees: assignees,
      work_item: work_item
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
  let(:reviewers) { nil }
  let(:assignees) { nil }
  let(:milestone) { nil }
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
  let(:work_item) { 123 }
  let(:custom_labels) { nil }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
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
  end

  describe "#create" do
    it "pushes a commit to Azure and creates a pull request" do
      creator.create

      expect(WebMock).
        to(
          have_requested(:post, "#{repo_api_url}/pushes?api-version=5.0").
            with do |req|
              json_body = JSON.parse(req.body)
              expect(json_body.fetch("commits").count).to eq(1)
              expect(json_body.fetch("commits").first.keys).
                to_not include("author")
            end
        )
      expect(WebMock).
        to have_requested(:post, "#{repo_api_url}/pullrequests?api-version=5.0")
    end

    context "with reviewers" do
      let(:reviewers) { ["0013-0006-1980"] }
      it "pushes a commit to Azure and creates a pull request with assigned reviewers" do
        creator.create

        expect(WebMock).
          to(
            have_requested(:post, "#{repo_api_url}/pullrequests?api-version=5.0").
            with do |req|
              reviewers = JSON.parse(req.body).fetch("reviewers")
              expect(reviewers.count).to eq(1)
              first_participant = reviewers.first
              expect(first_participant.fetch("id")).
                 to eq("0013-0006-1980")
              expect(first_participant.fetch("isRequired")).
                 to eq(true)
            end
          )
      end
    end

    context "with assignees" do
      let(:assignees) { ["0013-0006-1980"] }
      it "pushes a commit to Azure and creates a pull request with assigned optional reviewers" do
        creator.create

        expect(WebMock).
          to(
            have_requested(:post, "#{repo_api_url}/pullrequests?api-version=5.0").
            with do |req|
              reviewers = JSON.parse(req.body).fetch("reviewers")
              expect(reviewers.count).to eq(1)
              first_participant = reviewers.first
              expect(first_participant.fetch("id")).
                to eq("0013-0006-1980")
              expect(first_participant.fetch("isRequired")).
                to eq(false)
            end
          )
      end
    end

    context "with e very long pr description" do
      let(:pr_description) { ("a" * 3997) + "💣 kaboom" }
      it "truncates the description respecting azures encoding" do
        creator.create

        expect(WebMock).
          to(
            have_requested(:post, "#{repo_api_url}/pullrequests?api-version=5.0").
            with do |req|
              description = JSON.parse(req.body).fetch("description")
              expect(description.length).to eq 4000
              expect(description).to end_with("\n\n_Description has been truncated_")
            end
          )
      end
    end

    context "with author details provided" do
      let(:author_details) do
        { email: "support@dependabot.com", name: "dependabot" }
      end

      it "includes the author details in the commit" do
        creator.create

        expect(WebMock).
          to(
            have_requested(:post, "#{repo_api_url}/pushes?api-version=5.0").
              with do |req|
                json_body = JSON.parse(req.body)
                expect(json_body.fetch("commits").count).to eq(1)
                expect(json_body.fetch("commits").first.fetch("author")).
                  to eq(author_details.transform_keys(&:to_s))
              end
          )
      end

      context "but are an empty hash" do
        let(:author_details) { {} }

        it "does not include the author details in the commit" do
          creator.create

          expect(WebMock).
            to(
              have_requested(:post, "#{repo_api_url}/pushes?api-version=5.0").
                with do |req|
                  json_body = JSON.parse(req.body)
                  expect(json_body.fetch("commits").count).to eq(1)
                  expect(json_body.fetch("commits").first.keys).
                    to_not include("author")
                end
            )
        end
      end
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

      context "and a pull request to this branch already exists" do
        before do
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
