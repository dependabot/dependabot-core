# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/api_client"

RSpec.describe Dependabot::ApiClient do
  subject(:client) { Dependabot::ApiClient.new("http://example.com", "token") }
  let(:headers) { { "Content-Type" => "application/json" } }

  describe "get_job" do
    before do
      stub_request(:get, "http://example.com/update_jobs/1").
        to_return(body: fixture("get_job.json"), headers: headers)
    end

    it "hits the correct endpoint" do
      client.get_job(1)

      expect(WebMock).
        to have_requested(:get, "http://example.com/update_jobs/1").
        with(headers: { "Authorization" => "token" })
    end

    it "returns a job" do
      job = client.get_job(1)
      expect(job).to be_a(Dependabot::Job)
    end
  end

  describe "create_pull_request" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        previous_version: "1.7.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
        ]
      )
    end
    let(:dependency_files) do
      [
        { name: "Gemfile", content: "some things" },
        { name: "Gemfile.lock", content: "more things" }
      ]
    end
    let(:create_pull_request_url) do
      "http://example.com/update_jobs/1/create_pull_request"
    end
    let(:base_commit) { "sha" }
    let(:message) { nil }

    before do
      stub_request(:post, create_pull_request_url).
        to_return(status: 204, headers: headers)
    end

    it "hits the correct endpoint" do
      client.create_pull_request(1, [dependency], dependency_files, base_commit, message)

      expect(WebMock).
        to have_requested(:post, create_pull_request_url).
        with(headers: { "Authorization" => "token" })
    end

    it "does not send pull request message" do
      client.create_pull_request(1, [dependency], dependency_files, base_commit, message)

      expect(WebMock).
        to(have_requested(:post, create_pull_request_url).
           with do |req|
             expect(req.body).not_to include("commit-message")
           end)
    end

    context "with pull request message" do
      let(:message) do
        Dependabot::PullRequestCreator::Message.new(
          pr_name: "PR name",
          pr_message: "PR message",
          commit_message: "Commit message"
        )
      end

      it "encodes fields" do
        client.create_pull_request(1, [dependency], dependency_files, base_commit, message)
        expect(WebMock).
          to(have_requested(:post, create_pull_request_url).
            with(headers: { "Authorization" => "token" }).
            with do |req|
              data = JSON.parse(req.body)["data"]
              expect(data["commit-message"]).to eq("Commit message")
              expect(data["pr-title"]).to eq("PR name")
              expect(data["pr-body"]).to eq("PR message")
              true
            end)
      end
    end

    context "with a removed dependency" do
      let(:removed_dependency) do
        Dependabot::Dependency.new(
          name: "removed",
          package_manager: "bundler",
          previous_version: "1.7.0",
          requirements: [],
          previous_requirements: [],
          removed: true
        )
      end

      it "encodes fields" do
        client.create_pull_request(1, [removed_dependency, dependency], dependency_files, base_commit, message)
        expect(WebMock).
          to(have_requested(:post, create_pull_request_url).
            with(headers: { "Authorization" => "token" }).
            with do |req|
              data = JSON.parse(req.body)["data"]
              expect(data["dependencies"].first["removed"]).to eq(true)
              expect(data["dependencies"].first.key?("version")).to eq(false)
              expect(data["dependencies"].last.key?("removed")).to eq(false)
              expect(data["dependencies"].last["version"]).to eq("1.8.0")
              true
            end)
      end
    end
  end

  describe "update_pull_request" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        previous_version: "1.7.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
        ]
      )
    end
    let(:dependency_files) do
      [
        { name: "Gemfile", content: "some things" },
        { name: "Gemfile.lock", content: "more things" }
      ]
    end
    let(:update_pull_request_url) do
      "http://example.com/update_jobs/1/update_pull_request"
    end
    let(:base_commit) { "sha" }

    before do
      stub_request(:post, update_pull_request_url).
        to_return(status: 204, headers: headers)
    end

    it "hits the correct endpoint" do
      client.update_pull_request(1, [dependency], dependency_files, base_commit)

      expect(WebMock).
        to have_requested(:post, update_pull_request_url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "close_pull_request" do
    let(:dependency_name) { "business" }
    let(:close_pull_request_url) do
      "http://example.com/update_jobs/1/close_pull_request"
    end

    before do
      stub_request(:post, close_pull_request_url).
        to_return(status: 204, headers: headers)
    end

    it "hits the correct endpoint" do
      client.close_pull_request(1, dependency_name, :dependency_removed)

      expect(WebMock).
        to have_requested(:post, close_pull_request_url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "record_update_job_error" do
    let(:url) { "http://example.com/update_jobs/1/record_update_job_error" }
    let(:error_type) { "dependency_file_not_evaluatable" }
    let(:error_detail) { { "message" => "My message" } }
    before { stub_request(:post, url).to_return(status: 204) }

    it "hits the correct endpoint" do
      client.record_update_job_error(
        1,
        error_type: error_type,
        error_details: error_detail
      )

      expect(WebMock).
        to have_requested(:post, url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "mark_job_as_processed" do
    let(:url) { "http://example.com/update_jobs/1/mark_as_processed" }
    let(:base_commit) { "sha" }
    before { stub_request(:patch, url).to_return(status: 204) }

    it "hits the correct endpoint" do
      client.mark_job_as_processed(1, base_commit)

      expect(WebMock).
        to have_requested(:patch, url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "update_dependency_list" do
    let(:url) { "http://example.com/update_jobs/1/update_dependency_list" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ]
      )
    end
    before { stub_request(:post, url).to_return(status: 204) }

    it "hits the correct endpoint" do
      client.update_dependency_list(1, [dependency], ["Gemfile"])

      expect(WebMock).
        to have_requested(:post, url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "record_package_manager_version" do
    let(:url) { "http://example.com/update_jobs/1/record_package_manager_version" }
    before { stub_request(:post, url).to_return(status: 204) }

    it "hits the correct endpoint" do
      client.record_package_manager_version(
        1, "bundler", { "bundler" => "2" }
      )

      expect(WebMock).
        to have_requested(:post, url).
        with(headers: { "Authorization" => "token" })
    end
  end
end
