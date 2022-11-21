# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers"
require "dependabot/end_to_end_job"
require "dependabot/api_client"
require "dependabot/instrumentation"

RSpec.describe Dependabot::EndToEndJob do
  subject(:end_to_end_job) { Dependabot::EndToEndJob.new }

  before { WebMock.disable! }
  after { WebMock.enable! }

  let(:job_id) { 1 }
  let(:api_client) { double(Dependabot::ApiClient) }

  before do
    allow(end_to_end_job).to receive(:api_client).and_return(api_client)
    allow(end_to_end_job).to receive(:job).and_return(job)
    allow(end_to_end_job).to receive(:job_id).and_return(1)
    allow(end_to_end_job).to receive(:token).and_return("token")
    allow(end_to_end_job).
      to receive(:dependency_files).and_return(dependency_files)
    allow(end_to_end_job).to receive(:base_commit_sha).and_return("sha")

    allow(api_client).to receive(:create_pull_request)
    allow(api_client).to receive(:update_pull_request)
    allow(api_client).to receive(:close_pull_request)
    allow(api_client).to receive(:mark_job_as_processed)
    allow(api_client).to receive(:update_dependency_list)
    allow(api_client).to receive(:record_update_job_error)
    # Recording the package manager happens via an observer so the instantiated `api_client` does not receive this call
    allow_any_instance_of(Dependabot::ApiClient).to receive(:record_package_manager_version)

    allow(Dependabot::Environment).to receive(:token).and_return("some_token")
    allow(Dependabot::Environment).to receive(:job_id).and_return(job_id)
    allow(Dependabot.logger).to receive(:info).and_call_original
    message_builder = double(Dependabot::PullRequestCreator::MessageBuilder)
    allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder)
    allow(message_builder).to receive(:message).and_return(nil)
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

    let(:job) do
      Dependabot::Job.new(
        token: "token",
        dependencies: nil,
        allowed_updates: [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        existing_pull_requests: [],
        ignore_conditions: [],
        security_advisories: [],
        package_manager: "bundler",
        source: {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }],
        lockfile_only: false,
        requirements_update_strategy: nil,
        update_subdependencies: false,
        updating_a_pull_request: false,
        vendor_dependencies: false,
        security_updates_only: false
      )
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
      end_to_end_job.run
    end

    it "summarizes the changes" do
      expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
        expect(log_message).to include("created", "dummy-pkg-b ( from 1.1.0 to 1.2.0 )")
      end

      end_to_end_job.run
    end

    it "instruments the package manager version" do
      expect_any_instance_of(Dependabot::ApiClient).to receive(:record_package_manager_version)

      end_to_end_job.run
    end

    context "when there is an exception that blocks PR creation" do
      before do
        allow(api_client).to receive(:create_pull_request).and_raise(StandardError, "oh no!")
      end

      it "notifies Dependabot API of the problem" do
        expect(api_client).to receive(:record_update_job_error).
          with(job_id, { error_type: "unknown_error", error_details: nil })

        expect { end_to_end_job.run }.to output(/oh no!/).to_stdout_from_any_process
      end

      it "indicates there was an error in the summary" do
        expect(Dependabot.logger).not_to receive(:info).with(/Changes to Dependabot Pull Requests/)
        expect(Dependabot.logger).to receive(:info).with(/Dependabot encountered '1' error/)

        expect { end_to_end_job.run }.to output(/oh no!/).to_stdout_from_any_process
      end

      it "does not raise an exception" do
        expect { end_to_end_job.run }.to output(/oh no!/).to_stdout_from_any_process
      end

      context "when GITHUB_ACTIONS is set" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?) { "true" }
        end

        it "raises an exception" do
          expect { end_to_end_job.run }.to raise_error(Dependabot::RunFailure).
            and output(/oh no!/).to_stdout_from_any_process
        end
      end
    end

    context "when there is an exception that does not block PR creation" do
      before do
        # Pre-populate an error in the service
        end_to_end_job.service.record_update_job_error(
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

        end_to_end_job.run
      end

      it "does not raise an exception" do
        expect { end_to_end_job.run }.not_to raise_error
      end

      context "when GITHUB_ACTIONS is set" do
        before do
          allow(Dependabot::Environment).to receive(:github_actions?) { "true" }
        end

        it "raises an exception" do
          expect { end_to_end_job.run }.to raise_error(Dependabot::RunFailure)
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

    let(:job) do
      Dependabot::Job.new(
        token: "token",
        dependencies: nil,
        allowed_updates: [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        existing_pull_requests: [],
        ignore_conditions: [],
        security_advisories: [],
        package_manager: "bundler",
        source: {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => test_access_token
        }],
        lockfile_only: false,
        requirements_update_strategy: nil,
        update_subdependencies: false,
        updating_a_pull_request: false,
        vendor_dependencies: false,
        security_updates_only: false
      )
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
      end_to_end_job.run
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

      end_to_end_job.run
    end
  end

  describe "JavaScript" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "package.json",
          content: fixture("npm/original/package.json"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "package-lock.json",
          content: fixture("npm/original/package-lock.json"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "yarn.lock",
          content: fixture("yarn/original/yarn.lock"),
          directory: "/"
        )
      ]
    end

    let(:job) do
      Dependabot::Job.new(
        token: "token",
        dependencies: nil,
        allowed_updates: [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        existing_pull_requests: [],
        ignore_conditions: [],
        security_advisories: [],
        package_manager: "npm_and_yarn",
        source: {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }],
        lockfile_only: false,
        requirements_update_strategy: nil,
        update_subdependencies: false,
        updating_a_pull_request: false,
        vendor_dependencies: false,
        security_updates_only: false
      )
    end

    it "updates dependencies correctly" do
      expect(api_client).
        to receive(:create_pull_request) do |id, deps, files, commit_sha|
          expect(id).to eq(1)
          dep = Dependabot::Dependency.new(
            name: "@dependabot/dummy-pkg-b",
            package_manager: "npm_and_yarn",
            version: "1.2.0",
            previous_version: "1.1.0",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.2.0",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }
            ],
            previous_requirements: [
              {
                file: "package.json",
                requirement: "^1.1.0",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }
            ]
          )
          expect(deps).to eql([dep])
          expect(files).to eq(
            [
              {
                "name" => "package.json",
                "content" => fixture("npm/updated/package.json"),
                "directory" => "/",
                "type" => "file",
                "mode" => nil,
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              },
              {
                "name" => "yarn.lock",
                "content" => fixture("yarn/updated/yarn.lock"),
                "directory" => "/",
                "type" => "file",
                "mode" => nil,
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              },
              {
                "name" => "package-lock.json",
                "content" => fixture("npm/updated/package-lock.json"),
                "directory" => "/",
                "type" => "file",
                "mode" => nil,
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              }
            ]
          )
          expect(commit_sha).to eq("sha")
        end
      end_to_end_job.run
    end

    it "summarizes the changes" do
      expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
        expect(log_message).to include("created", "dummy-pkg-b ( from 1.1.0 to 1.2.0 )")
      end

      end_to_end_job.run
    end
  end

  describe "composer" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "composer.json",
          content: fixture("composer/original/composer.json"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "composer.lock",
          content: fixture("composer/original/composer.lock"),
          directory: "/"
        )
      ]
    end

    let(:job) do
      Dependabot::Job.new(
        token: "token",
        dependencies: nil,
        allowed_updates: [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          },
          {
            "dependency-type" => "indirect",
            "update-type" => "security"
          }
        ],
        existing_pull_requests: [],
        ignore_conditions: [],
        security_advisories: [],
        package_manager: "composer",
        source: {
          "provider" => "github",
          "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
          "directory" => "/",
          "api-endpoint" => "https://api.github.com/",
          "hostname" => "github.com",
          "branch" => nil
        },
        credentials: [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }],
        lockfile_only: false,
        requirements_update_strategy: :bump_versions,
        update_subdependencies: false,
        updating_a_pull_request: false,
        vendor_dependencies: false,
        security_updates_only: false
      )
    end

    it "updates dependencies correctly" do
      expect(api_client).
        to receive(:create_pull_request) do |id, deps, files, commit_sha|
          expect(id).to eq(1)
          dep = Dependabot::Dependency.new(
            name: "dependabot/dummy-pkg-b",
            package_manager: "composer",
            version: "1.2.0",
            previous_version: "1.1.0",
            requirements: [
              {
                file: "composer.json",
                requirement: "^1.2.0",
                source: {
                  type: "git",
                  url: "https://github.com/dependabot/php-dummy-pkg-b.git"
                },
                groups: ["runtime"]
              }
            ],
            previous_requirements: [
              {
                file: "composer.json",
                requirement: "^1.1.0",
                source: {
                  type: "git",
                  url: "https://github.com/dependabot/php-dummy-pkg-b.git"
                },
                groups: ["runtime"]
              }
            ]
          )
          expect(deps).to eql([dep])
          expect(files).to eq(
            [
              {
                "name" => "composer.json",
                "content" => fixture("composer/updated/composer.json"),
                "directory" => "/",
                "type" => "file",
                "mode" => nil,
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              },
              {
                "name" => "composer.lock",
                "content" => fixture("composer/updated/composer.lock"),
                "directory" => "/",
                "type" => "file",
                "mode" => nil,
                "support_file" => false,
                "content_encoding" => "utf-8",
                "deleted" => false,
                "operation" => "update"
              }
            ]
          )
          expect(commit_sha).to eq("sha")
        end
      end_to_end_job.run
    end

    it "summarizes the changes" do
      expect(Dependabot.logger).to receive(:info).with(/Changes to Dependabot Pull Requests/) do |log_message|
        expect(log_message).to include("created", "dummy-pkg-b ( from 1.1.0 to 1.2.0 )")
      end

      end_to_end_job.run
    end
  end
end
