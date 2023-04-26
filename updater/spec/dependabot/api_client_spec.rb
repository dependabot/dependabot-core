# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_change"
require "dependabot/api_client"

RSpec.describe Dependabot::ApiClient do
  subject(:client) { Dependabot::ApiClient.new("http://example.com", 1, "token") }
  let(:headers) { { "Content-Type" => "application/json" } }

  describe "create_pull_request" do
    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: dependencies,
        updated_dependency_files: dependency_files
      )
    end
    let(:job) do
      instance_double(Dependabot::Job,
                      source: nil,
                      credentials: [],
                      commit_message_options: [],
                      updating_a_pull_request?: false)
    end
    let(:dependencies) do
      [dependency]
    end
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
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "some things",
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: "more things",
          directory: "/"
        )
      ]
    end
    let(:create_pull_request_url) do
      "http://example.com/update_jobs/1/create_pull_request"
    end
    let(:base_commit) { "sha" }
    let(:message) do
      Dependabot::PullRequestCreator::Message.new(
        pr_name: "PR name",
        pr_message: "PR message",
        commit_message: "Commit message"
      )
    end

    before do
      allow(Dependabot::PullRequestCreator::MessageBuilder).to receive_message_chain(:new, :message).and_return(message)

      stub_request(:post, create_pull_request_url).
        to_return(status: 204, headers: headers)
    end

    it "hits the correct endpoint" do
      client.create_pull_request(dependency_change, base_commit)

      expect(WebMock).
        to have_requested(:post, create_pull_request_url).
        with(headers: { "Authorization" => "token" })
    end

    it "encodes the payload correctly fields" do
      client.create_pull_request(dependency_change, base_commit)

      expect(WebMock).to(have_requested(:post, create_pull_request_url).with do |req|
        data = JSON.parse(req.body)["data"]

        expect(data["dependencies"]).to eq([
          {
            "name" => "business",
            "previous-requirements" =>
            [
              {
                "file" => "Gemfile",
                "groups" => [],
                "requirement" => "~> 1.7.0",
                "source" => nil
              }
            ],
            "previous-version" => "1.7.0",
            "requirements" =>
              [
                {
                  "file" => "Gemfile",
                  "groups" => [],
                  "requirement" => "~> 1.8.0",
                  "source" => nil
                }
              ],
            "version" => "1.8.0"
          }
        ])
        expect(data["updated-dependency-files"]).to eql([
          {
            "content" => "some things",
            "content_encoding" => "utf-8",
            "deleted" => false,
            "directory" => "/",
            "mode" => "100644",
            "name" => "Gemfile",
            "operation" => "update",
            "support_file" => false,
            "type" => "file"
          },
          { "content" => "more things",
            "content_encoding" => "utf-8",
            "deleted" => false,
            "directory" => "/",
            "mode" => "100644",
            "name" => "Gemfile.lock",
            "operation" => "update",
            "support_file" => false,
            "type" => "file" }
        ])
        expect(data["base-commit-sha"]).to eql("sha")
        expect(data["commit-message"]).to eq("Commit message")
        expect(data["pr-title"]).to eq("PR name")
        expect(data["pr-body"]).to eq("PR message")
      end)
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

      let(:dependencies) do
        [removed_dependency, dependency]
      end

      it "encodes fields" do
        client.create_pull_request(dependency_change, base_commit)
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

    context "grouped updates" do
      it "does not include the dependency-group key by default" do
        client.create_pull_request(dependency_change, base_commit)

        expect(WebMock).
          to(have_requested(:post, create_pull_request_url).
             with do |req|
               expect(req.body).not_to include("dependency-group")
             end)
      end

      it "flags the PR as having dependency-groups if the dependency change has a dependency group assigned" do
        group = Dependabot::DependencyGroup.new(name: "dummy-group-name", rules: ["*"])

        grouped_dependency_change = Dependabot::DependencyChange.new(
          job: job,
          updated_dependencies: dependencies,
          updated_dependency_files: dependency_files,
          dependency_group: group
        )

        client.create_pull_request(grouped_dependency_change, base_commit)

        expect(WebMock).
          to(have_requested(:post, create_pull_request_url).
             with do |req|
               data = JSON.parse(req.body)["data"]
               expect(data["dependency-group"]).to eq({ "name" => "dummy-group-name" })
             end)
      end
    end
  end

  describe "update_pull_request" do
    let(:dependency_change) do
      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: [dependency],
        updated_dependency_files: dependency_files
      )
    end
    let(:job) do
      instance_double(Dependabot::Job,
                      source: nil,
                      credentials: [],
                      commit_message_options: [],
                      updating_a_pull_request?: true)
    end
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
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "some things",
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: "more things",
          directory: "/"
        )
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
      client.update_pull_request(dependency_change, base_commit)

      expect(WebMock).
        to have_requested(:post, update_pull_request_url).
        with(headers: { "Authorization" => "token" })
    end

    it "does not encode the pull request fields" do
      expect(Dependabot::PullRequestCreator::MessageBuilder).not_to receive(:new)

      client.update_pull_request(dependency_change, base_commit)

      expect(WebMock).
        to(have_requested(:post, update_pull_request_url).with do |req|
             data = JSON.parse(req.body)["data"]

             expect(data["dependency-names"]).to eq(["business"])
             expect(data["updated-dependency-files"]).to eql([
               {
                 "content" => "some things",
                 "content_encoding" => "utf-8",
                 "deleted" => false,
                 "directory" => "/",
                 "mode" => "100644",
                 "name" => "Gemfile",
                 "operation" => "update",
                 "support_file" => false,
                 "type" => "file"
               },
               { "content" => "more things",
                 "content_encoding" => "utf-8",
                 "deleted" => false,
                 "directory" => "/",
                 "mode" => "100644",
                 "name" => "Gemfile.lock",
                 "operation" => "update",
                 "support_file" => false,
                 "type" => "file" }
             ])
             expect(data["base-commit-sha"]).to eql("sha")
             expect(data).not_to have_key("commit-message")
             expect(data).not_to have_key("pr-title")
             expect(data).not_to have_key("pr-body")
             expect(data).not_to have_key("grouped-update")
           end)
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
      client.close_pull_request(dependency_name, :dependency_removed)

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
      client.mark_job_as_processed(base_commit)

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
      client.update_dependency_list([dependency], ["Gemfile"])

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
        "bundler", { "bundler" => "2" }
      )

      expect(WebMock).
        to have_requested(:post, url).
        with(headers: { "Authorization" => "token" })
    end
  end

  describe "increment_metric" do
    let(:url) { "http://example.com/update_jobs/1/increment_metric" }
    before { stub_request(:post, url).to_return(status: 204) }

    context "when successful" do
      before { stub_request(:post, url).to_return(status: 204) }

      it "hits the expected endpoint" do
        client.increment_metric("apples", tags: { red: 1, green: 2 })

        expect(WebMock).
          to have_requested(:post, url).
          with(headers: { "Authorization" => "token" })
      end
    end

    context "when unsuccessful" do
      before do
        stub_request(:post, url).to_return(status: 401)
        allow(Dependabot.logger).to receive(:debug)
      end

      it "logs a debug notice" do
        client.increment_metric("apples", tags: { red: 1, green: 2 })

        expect(WebMock).
          to have_requested(:post, url).
          with(headers: { "Authorization" => "token" })

        expect(Dependabot.logger).to have_received(:debug).with(
          "Unable to report metric 'apples'."
        )
      end
    end
  end
end
