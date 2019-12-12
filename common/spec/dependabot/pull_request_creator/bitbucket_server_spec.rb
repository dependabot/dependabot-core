# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/bitbucket_server"

RSpec.describe Dependabot::PullRequestCreator::BitbucketServer do
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
      reviewers: reviewers
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "bitbucket_server",
      repo: "projects/gocardless/repos/bump",
      api_endpoint: "https://bitbucket.com/rest/api/1.0",
      hostname: "bitbucket.com"
    )
  end
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }
  let(:base_commit) { "basecommitsha" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "bitbucket.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:commit_message) { "Commit msg" }
  let(:pr_description) { "PR msg" }
  let(:pr_name) { "PR name" }
  let(:reviewers) { nil }
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
  let(:multipart_header) { { "Content-Type" => "multipart/form-data" } }
  let(:repo_api_url) do
    "https://bitbucket.com/rest/api/1.0/projects/gocardless/repos/bump"
  end

  before do
    stub_request(:get, repo_api_url).
      to_return(status: 200,
                body: fixture("bitbucket_server", "bump_repo.json"),
                headers: json_header)
    stub_request(
      :get,
      "#{repo_api_url}/branches?filterText=#{CGI.escape(branch_name)}"
    ).to_return(
      status: 200,
      body: fixture("bitbucket_server", "branch_not_found.json"),
      headers: json_header
    )
    stub_request(:post, "#{repo_api_url}/branches").
      to_return(status: 200,
                headers: json_header)
    stub_request(:get, "#{repo_api_url}/commits?limit=1&" \
                 "start=0&until=#{branch_name}&path=Gemfile").
      to_return(status: 200,
                body: fixture("bitbucket_server", "gemfile_commit.json"),
                headers: json_header)
    stub_request(:get, "#{repo_api_url}/commits?limit=1&" \
                 "start=0&until=#{branch_name}&path=Gemfile.lock").
      to_return(status: 200,
                body: fixture("bitbucket_server", "gemfile_lock_commit.json"),
                headers: json_header)
    stub_request(:get, "#{repo_api_url}/branches/default").
      to_return(body: fixture("bitbucket_server", "default_branch.json"),
                headers: json_header)
    stub_request(:put, "#{repo_api_url}/browse/Gemfile").
      to_return(status: 200,
                headers: multipart_header)
    stub_request(:put, "#{repo_api_url}/browse/Gemfile.lock").
      to_return(status: 200,
                headers: multipart_header)
    stub_request(:post, "#{repo_api_url}/pull-requests").
      to_return(status: 200,
                headers: json_header)
  end

  describe "#create" do
    it "pushes a commit to Bitbucket server and creates a pull request" do
      creator.create

      expect(WebMock).to have_requested(
        :put, "#{repo_api_url}/browse/Gemfile"
      )
      expect(WebMock).to have_requested(
        :put, "#{repo_api_url}/browse/Gemfile.lock"
      )
      expect(WebMock).to have_requested(
        :post, "#{repo_api_url}/pull-requests"
      )
    end

    context "when the branch already exists" do
      before do
        stub_request(
          :get,
          "#{repo_api_url}/branches?filterText=#{branch_name}"
        ).to_return(
          status: 200,
          body: fixture("bitbucket_server", "branch_found.json"),
          headers: json_header
        )
      end

      context "but a pull request to this branch doesn't" do
        before do
          stub_request(
            :get,
            "#{repo_api_url}/pull-requests?" \
            "at=refs/heads/#{branch_name}" \
            "&direction=outgoing"
          ).to_return(
            status: 200,
            body: fixture("bitbucket_server", "branch_not_found.json"),
            headers: json_header
          )
        end

        context "when a commit doesn't exist" do
          before do
            stub_request(:get,
                         "#{repo_api_url}/commits?" \
                         "limit=1&start=0&until=#{branch_name}").
              to_return(status: 200,
                        body: fixture("bitbucket_server",
                                      "gemfile_commit.json"),
                        headers: json_header)
          end

          it "creates a commit and pull request with the right details" do
            expect(creator.create).to_not be_nil

            expect(WebMock).
              to have_requested(
                :put,
                "#{repo_api_url}/browse/Gemfile"
              )
            expect(WebMock).
              to have_requested(
                :put,
                "#{repo_api_url}/browse/Gemfile.lock"
              )
            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pull-requests"
              )
          end
        end

        context "when a commit already exists" do
          before do
            stub_request(:get,
                         "#{repo_api_url}/commits?" \
                         "limit=1&start=0&until=#{branch_name}").
              to_return(status: 200,
                        body: fixture("bitbucket_server", "latest_commit.json"),
                        headers: json_header)
          end

          it "creates only a pull request with the right details" do
            expect(creator.create).to_not be_nil

            expect(WebMock).
              not_to have_requested(
                :put,
                "#{repo_api_url}/browse/Gemfile"
              )
            expect(WebMock).
              not_to have_requested(
                :put,
                "#{repo_api_url}/browse/Gemfile.lock"
              )
            expect(WebMock).
              to have_requested(
                :post,
                "#{repo_api_url}/pull-requests"
              )
          end
        end
      end

      context "and a pull request to this branch already exists" do
        before do
          stub_request(
            :get,
            "#{repo_api_url}/pull-requests?" \
            "at=refs/heads/#{branch_name}" \
            "&direction=outgoing"
          ).to_return(
            status: 200,
            body: fixture("bitbucket_server", "pull_request.json"),
            headers: json_header
          )
        end

        it "doesn't create a commit or pull request (and returns nil)" do
          expect(creator.create).to be_nil

          expect(WebMock).
            to_not have_requested(
              :put,
              "#{repo_api_url}/browse/Gemfile"
            )
          expect(WebMock).
            to_not have_requested(
              :put,
              "#{repo_api_url}/browse/Gemfile.lock"
            )
          expect(WebMock).
            to_not have_requested(
              :post,
              "#{repo_api_url}/pull-requests"
            )
        end
      end
    end
  end
end
