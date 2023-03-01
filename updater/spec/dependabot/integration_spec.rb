# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers"

require "dependabot/file_fetcher_command"
require "dependabot/update_files_command"

require "dependabot/api_client"

RSpec.describe "Dependabot Updates" do
  let(:fetch_files) { Dependabot::FileFetcherCommand.new }
  let(:update_files) { Dependabot::UpdateFilesCommand.new }

  let(:run_job) do
    fetch_files.run
    update_files.run
  end

  before { WebMock.disable! }
  after { WebMock.enable! }

  let(:job_id) { 1 }
  let(:output_path) do
    File.join(Dir.mktmpdir, "output.json")
  end

  let(:fetch_job_definition) do
    # for the fetch step, the definition is just the parameters
    {
      "job" => job_parameters
    }
  end

  let(:update_job_definition) do
    # for the update step, we expect the base commit sha and files to be prepared
    # by the previous step
    fetch_job_definition.merge({
      "base_commit_sha" => "sha",
      "base64_dependency_files" => dependency_files.map do |file|
        base64_file = file.dup
        base64_file.content = Base64.encode64(file.content) unless file.binary?
        base64_file.to_h
      end
    })
  end

  let(:api_client) do
    instance_double(Dependabot::ApiClient,
                    create_pull_request: nil,
                    update_pull_request: nil,
                    close_pull_request: nil,
                    mark_job_as_processed: nil,
                    update_dependency_list: nil,
                    record_update_job_error: nil,
                    record_package_manager_version: nil)
  end
  let(:file_fetcher) do
    instance_double(Dependabot::FileFetchers::Base,
                    files: dependency_files,
                    commit: "sha",
                    package_manager_version: nil)
  end
  let(:message_builder) do
    instance_double(Dependabot::PullRequestCreator::MessageBuilder, message: nil)
  end

  before do
    # Stub out the environment
    allow(Dependabot::Environment).to receive(:job_id).and_return(job_id)
    allow(Dependabot::Environment).to receive(:job_definition).and_return(
      fetch_job_definition,
      update_job_definition
    )
    allow(Dependabot::Environment).to receive(:output_path).and_return(
      File.join(Dir.mktmpdir, "fetch/output.json"),
      File.join(Dir.mktmpdir, "update/output.json")
    )
    allow(Dependabot::Environment).to receive(:token).and_return("token")

    # Stub Dependabot object with instance doubles
    allow(Dependabot::ApiClient).to receive(:new).and_return(api_client)
    # Recording the package manager happens via an observer so the instantiated `api_client` does not receive this call
    allow_any_instance_of(Dependabot::ApiClient).to receive(:record_package_manager_version)
    allow(Dependabot::FileFetchers).to receive_message_chain(:for_package_manager, :new).and_return(file_fetcher)
    allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder)

    allow(Dependabot.logger).to receive(:info).and_call_original
  end

  describe "bundler" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: "/"
        )
      ]
    end

    let(:job_parameters) do
      {
        "token" => "token",
        "dependencies" => nil,
        "allowed_updates" => [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        "existing_pull_requests" => [],
        "ignore_conditions" => [],
        "security_advisories" => [],
        "package_manager" => "bundler",
        "source" => {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        "credentials" => [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }],
        "lockfile_only" => false,
        "requirements_update_strategy" => nil,
        "update_subdependencies" => false,
        "updating_a_pull_request" => false,
        "vendor_dependencies" => false,
        "security_updates_only" => false
      }
    end

    it "updates dependencies correctly" do
      expect(api_client).
        to receive(:create_pull_request) do |id, deps, files, commit_sha|
          expect(id).to eq(1)
          dep = Dependabot::Dependency.new(
            name: "dummy-pkg-b",
            package_manager: "bundler",
            version: "1.2.0",
            previous_version: "1.1.0",
            requirements: [
              { requirement: "~> 1.2.0",
                groups: [:default],
                source: nil,
                file: "Gemfile" }
            ],
            previous_requirements: [
              { requirement: "~> 1.1.0",
                groups: [:default],
                source: nil,
                file: "Gemfile" }
            ]
          )
          expect(deps).to eql([dep])
          expect(files).to eq(
            [
              {
                "name" => "Gemfile",
                "content" => fixture("bundler/updated/Gemfile"),
                "directory" => "/",
                "type" => "file",
                "mode" => "100644",
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              },
              {
                "name" => "Gemfile.lock",
                "content" => fixture("bundler/updated/Gemfile.lock"),
                "directory" => "/",
                "type" => "file",
                "mode" => "100644",
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              }
            ]
          )
          expect(commit_sha).to eq("sha")
        end
      run_job
    end

    it "summarizes the changes" do
      expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
        expect(log_message).to include("created", "dummy-pkg-b ( from 1.1.0 to 1.2.0 )")
      end

      run_job
    end

    context "when there is an exception that blocks PR creation" do
      before do
        allow(api_client).to receive(:create_pull_request).and_raise(StandardError, "oh no!")
      end

      it "notifies Dependabot API of the problem" do
        expect(api_client).to receive(:record_update_job_error).
          with(job_id, { error_type: "unknown_error", error_details: nil })

        expect { run_job }.to output(/oh no!/).to_stdout_from_any_process
      end

      it "indicates there was an error in the summary" do
        expect(Dependabot.logger).not_to receive(:info).with(/Changes to Dependabot Pull Requests/)
        expect(Dependabot.logger).to receive(:info).with(/Dependabot encountered '1' error/)

        expect { run_job }.to output(/oh no!/).to_stdout_from_any_process
      end

      it "does not raise an exception" do
        expect { run_job }.to output(/oh no!/).to_stdout_from_any_process
      end

      context "when GITHUB_ACTIONS is set" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?) { "true" }
        end

        it "raises an exception" do
          expect { run_job }.to raise_error(Dependabot::RunFailure).
            and output(/oh no!/).to_stdout_from_any_process
        end
      end
    end

    context "when there is an exception that does not block PR creation" do
      before do
        # Pre-populate an updater error
        update_files.service.record_update_job_error(
          job_id,
          error_type: :epoch_error,
          error_details: {
            message: "What is fortran doing here?!"
          }
        )
      end

      it "indicates both the pr creation and error in the summary" do
        expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
          expect(log_message).to include("created", "dummy-pkg-b ( from 1.1.0 to 1.2.0 )")
          expect(log_message).to include("Dependabot encountered '1' error")
        end

        run_job
      end

      it "does not raise an exception" do
        expect { run_job }.not_to raise_error
      end

      context "when GITHUB_ACTIONS is set" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?) { "true" }
        end

        it "raises an exception" do
          expect { run_job }.to raise_error(Dependabot::RunFailure)
        end
      end
    end
  end

  describe "bundler git dependencies" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_git/original/Gemfile"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_git/original/Gemfile.lock"),
          directory: "/"
        )
      ]
    end

    let(:job_parameters) do
      {
        "token" => "token",
        "dependencies" => nil,
        "allowed_updates" => [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        "existing_pull_requests" => [],
        "ignore_conditions" => [],
        "security_advisories" => [],
        "package_manager" => "bundler",
        "source" => {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        "credentials" => [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => test_access_token
        }],
        "lockfile_only" => false,
        "requirements_update_strategy" => nil,
        "update_subdependencies" => false,
        "updating_a_pull_request" => false,
        "vendor_dependencies" => false,
        "security_updates_only" => false
      }
    end

    it "updates dependencies correctly" do
      expect(api_client).
        to receive(:create_pull_request) do |id, deps, files, commit_sha|
          expect(id).to eq(1)
          dep = Dependabot::Dependency.new(
            name: "dummy-git-dependency",
            package_manager: "bundler",
            version: "c0e25c2eb332122873f73acb3b61fb2e261cfd8f",
            previous_version: "20151f9b67c8a04461fa0ee28385b6187b86587b",
            requirements: [
              { requirement: ">= 0",
                groups: [:default],
                source: {
                  type: "git",
                  branch: nil,
                  ref: "v1.1.0",
                  url: "git@github.com:dependabot-fixtures/ruby-dummy-git-" \
                       "dependency.git"
                },
                file: "Gemfile" }
            ],
            previous_requirements: [
              { requirement: ">= 0",
                groups: [:default],
                source: {
                  type: "git",
                  branch: nil,
                  ref: "v1.0.0",
                  url: "git@github.com:dependabot-fixtures/ruby-dummy-git-" \
                       "dependency.git"
                },
                file: "Gemfile" }
            ]
          )
          expect(deps).to eql([dep])
          expect(files).to eq(
            [
              {
                "name" => "Gemfile",
                "content" => fixture("bundler_git/updated/Gemfile"),
                "directory" => "/",
                "type" => "file",
                "mode" => "100644",
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              },
              {
                "name" => "Gemfile.lock",
                "content" => fixture("bundler_git/updated/Gemfile.lock"),
                "directory" => "/",
                "type" => "file",
                "mode" => "100644",
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              }
            ]
          )
          expect(commit_sha).to eq("sha")
        end
      run_job
    end

    it "summarizes the changes" do
      expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
        expect(log_message).to include(
          "created",
          "dummy-git-dependency",
          "from 20151f9b67c8a04461fa0ee28385b6187b86587b",
          "to c0e25c2eb332122873f73acb3b61fb2e261cfd8f"
        )
      end

      run_job
    end
  end
end
