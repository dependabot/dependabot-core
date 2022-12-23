# frozen_string_literal: true

require "spec_helper"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_fetchers"
require "dependabot/updater"
require "dependabot/service"

RSpec.describe Dependabot::Updater do
  subject(:updater) do
    Dependabot::Updater.new(
      service: service,
      job_id: 1,
      job: job,
      dependency_files: dependency_files,
      base_commit_sha: "sha",
      repo_contents_path: repo_contents_path
    )
  end

  let(:logger) { double(Logger) }
  let(:service) { double(Dependabot::Service) }

  before do
    allow(service).to receive(:get_job).and_return(job)
    allow(service).to receive(:create_pull_request)
    allow(service).to receive(:update_pull_request)
    allow(service).to receive(:close_pull_request)
    allow(service).to receive(:mark_job_as_processed)
    allow(service).to receive(:update_dependency_list)
    allow(service).to receive(:record_update_job_error)
    allow_any_instance_of(Dependabot::ApiClient).to receive(:record_package_manager_version)
    allow(Dependabot).to receive(:logger).and_return(logger)
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)

    allow(Dependabot::Environment).to receive(:token).and_return("some_token")
    allow(Dependabot::Environment).to receive(:job_id).and_return(1)
  end

  let(:job) do
    Dependabot::Job.new(
      token: "token",
      dependencies: requested_dependencies,
      allowed_updates: allowed_updates,
      existing_pull_requests: existing_pull_requests,
      ignore_conditions: ignore_conditions,
      security_advisories: security_advisories,
      package_manager: "bundler",
      source: {
        "provider" => "github",
        "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
        "directory" => "/",
        "branch" => nil,
        "api-endpoint" => "https://api.github.com/",
        "hostname" => "github.com"
      },
      credentials: credentials,
      lockfile_only: false,
      requirements_update_strategy: nil,
      update_subdependencies: false,
      updating_a_pull_request: updating_a_pull_request,
      vendor_dependencies: false,
      experiments: experiments,
      commit_message_options: {
        "prefix" => commit_message_prefix,
        "prefix-development" => commit_message_prefix_development,
        "include-scope" => commit_message_include_scope
      },
      security_updates_only: security_updates_only
    )
  end
  let(:requested_dependencies) { nil }
  let(:updating_a_pull_request) { false }
  let(:existing_pull_requests) { [] }
  let(:security_advisories) { [] }
  let(:ignore_conditions) { [] }
  let(:security_updates_only) { false }
  let(:ignore_conditions) { [] }
  let(:allowed_updates) do
    [
      {
        "dependency-type" => "direct",
        "update-type" => "all"
      },
      {
        "dependency-type" => "indirect",
        "update-type" => "security"
      }
    ]
  end
  let(:credentials) do
    [
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "github-token"
      },
      { "type" => "random", "secret" => "codes" }
    ]
  end
  let(:experiments) { {} }
  let(:repo_contents_path) { nil }
  let(:commit_message_prefix) { "[bump]" }
  let(:commit_message_prefix_development) { "[bump-dev]" }
  let(:commit_message_include_scope) { true }

  let(:checker) { double(Dependabot::Bundler::UpdateChecker) }
  before do
    allow(checker).to receive(:up_to_date?).and_return(false, false)
    allow(checker).to receive(:vulnerable?).and_return(false)
    allow(checker).to receive(:version_class).
      and_return(Dependabot::Bundler::Version)
    allow(checker).to receive(:requirements_unlocked_or_can_be?).
      and_return(true)
    allow(checker).
      to receive(:can_update?).with(requirements_to_unlock: :own).
      and_return(true, false)
    allow(checker).
      to receive(:can_update?).with(requirements_to_unlock: :all).
      and_return(false)
    allow(checker).to receive(:updated_dependencies).and_return([dependency])
    allow(checker).to receive(:dependency).and_return(original_dependency)
    allow(checker).
      to receive(:latest_version).
      and_return(Gem::Version.new("1.2.0"))
    allow(Dependabot::Bundler::UpdateChecker).to receive(:new).and_return(checker)
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-b",
      package_manager: "bundler",
      version: "1.2.0",
      previous_version: "1.1.0",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.2.0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: "~> 1.1.0", groups: [], source: nil }
      ]
    )
  end
  let(:multiple_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "dummy-pkg-b",
        package_manager: "bundler",
        version: "1.2.0",
        previous_version: "1.1.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.2.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.1.0", groups: [], source: nil }
        ]
      ),
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        package_manager: "bundler",
        version: "2.0.0",
        previous_version: "1.0.1",
        requirements: [
          { file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.0.0", groups: [], source: nil }
        ]
      )
    ]
  end
  let(:original_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-b",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.1.0", groups: [], source: nil }
      ]
    )
  end

  describe "#run" do
    before do
      allow_any_instance_of(Bundler::CompactIndexClient::Updater).
        to receive(:etag_for).
        and_return("")

      stub_request(:get, "https://index.rubygems.org/versions").
        to_return(status: 200, body: fixture("rubygems-index"))

      stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-a").
        to_return(status: 200, body: fixture("rubygems-info-a"))
      stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-b").
        to_return(status: 200, body: fixture("rubygems-info-b"))

      message_builder = double(Dependabot::PullRequestCreator::MessageBuilder)
      allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder)
      allow(message_builder).to receive(:message).and_return(nil)
    end

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

    context "when the host is out of disk space" do
      before do
        allow(service).to receive(:record_update_job_error).and_return(nil)
        allow(job).to receive(:updating_a_pull_request?).and_raise(Errno::ENOSPC)
      end

      it "records an 'out_of_disk' error" do
        updater.run

        expect(service).to have_received(:record_update_job_error).
          with(anything, { error_type: "out_of_disk", error_details: nil })
      end
    end

    context "when github pr creation is rate limiting" do
      let(:experiments) { { "build-pull-request-message" => true } }

      before do
        allow(service).to receive(:record_update_job_error).and_return(nil)

        error = Octokit::TooManyRequests.new({
          status: 403,
          response_headers: { "X-RateLimit-Reset" => 42 }
        })
        message_builder = double(Dependabot::PullRequestCreator::MessageBuilder)
        allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder)
        allow(message_builder).to receive(:message).and_raise(error)
      end

      it "records an 'octokit_rate_limited' error" do
        updater.run

        expect(service).to have_received(:record_update_job_error).
          with(anything, { error_type: "octokit_rate_limited", error_details: { "rate-limit-reset": 42 } })
      end
    end

    context "when the job has already been processed" do
      let(:job) { nil }

      it "no-ops" do
        expect(updater).to_not receive(:dependencies)
        updater.run
      end
    end

    it "logs the current and latest versions" do
      expect(logger).
        to receive(:info).
        with("<job_1> Checking if dummy-pkg-b 1.1.0 needs updating")
      expect(logger).
        to receive(:info).
        with("<job_1> Latest version is 1.2.0")
      updater.run
    end

    context "when the checker has an requirements update strategy" do
      before do
        allow(checker).
          to receive(:requirements_update_strategy).
          and_return(:bump_versions)
      end

      it "logs the update requirements and strategy" do
        expect(logger).
          to receive(:info).
          with("<job_1> Requirements to unlock own")
        expect(logger).
          to receive(:info).
          with("<job_1> Requirements update strategy bump_versions")
        updater.run
      end
    end

    context "when no dependencies are allowed" do
      let(:allowed_updates) { [{ "dependency-name" => "typoed-dep-name" }] }

      it "logs the current and latest versions" do
        expect(logger).
          to receive(:info).
          with("<job_1> Found no dependencies to update after filtering " \
               "allowed updates")
        updater.run
      end
    end

    context "for security only updates" do
      let(:security_updates_only) { true }
      let(:security_advisories) do
        [{ "dependency-name" => "dummy-pkg-b",
           "affected-versions" => ["1.1.0"],
           "patched-versions" => ["1.2.0"] }]
      end

      before do
        allow(checker).to receive(:vulnerable?).and_return(true)
      end

      it "creates the pull request" do
        expect(service).to receive(:create_pull_request).once
        updater.run
      end

      context "when the dep has no version so we can't check vulnerability" do
        let(:original_dependency) do
          Dependabot::Dependency.new(
            name: "dummy-pkg-b",
            package_manager: "bundler",
            version: nil,
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.1.0",
                groups: [],
                source: nil
              }
            ]
          )
        end

        before do
          allow(checker).to receive(:vulnerable?).and_return(false)
        end

        it "does not create pull request" do
          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            1,
            {
              error_type: "dependency_file_not_supported",
              error_details: {
                "dependency-name": "dummy-pkg-b"
              }
            }
          )
          expect(logger).
            to receive(:info).with(
              "<job_1> Dependabot can't update vulnerable dependencies for " \
              "projects without a lockfile or pinned version requirement as " \
              "the currently installed version of dummy-pkg-b isn't known."
            )

          updater.run
        end
      end

      context "when the dependency is no longer vulnerable" do
        let(:security_advisories) do
          [{ "dependency-name" => "dummy-pkg-b",
             "affected-versions" => ["1.0.0"],
             "patched-versions" => ["1.1.0"] }]
        end

        before do
          allow(checker).to receive(:vulnerable?).and_return(false)
        end

        it "does not create pull request" do
          expect(service).to_not receive(:create_pull_request)
          updater.run
        end
      end

      context "when the update is still vulnerable" do
        let(:security_advisories) do
          [{ "dependency-name" => "dummy-pkg-b",
             "affected-versions" => ["1.1.0", "1.2.0"] }]
        end

        before do
          allow(checker).to receive(:vulnerable?).and_return(true)
        end

        it "does not create pull request" do
          expect(checker).to receive(:lowest_resolvable_security_fix_version).
            and_return(dependency.version)
          expect(checker).to receive(:lowest_security_fix_version).
            and_return(Dependabot::Bundler::Version.new("1.3.0"))
          expect(checker).to receive(:conflicting_dependencies).and_return(
            [
              {
                "explanation" =>
                  "dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.2.0)",
                "name" => "dummy-pkg-a",
                "version" => "1.0.0",
                "requirement" => "= 1.2.0"
              }
            ]
          )

          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            1,
            {
              error_type: "security_update_not_possible",
              error_details: {
                "dependency-name": "dummy-pkg-b",
                "latest-resolvable-version": "1.2.0",
                "lowest-non-vulnerable-version": "1.3.0",
                "conflicting-dependencies": [
                  {
                    "explanation" =>
                      "dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.2.0)",
                    "name" => "dummy-pkg-a",
                    "version" => "1.0.0",
                    "requirement" => "= 1.2.0"
                  }
                ]
              }
            }
          )
          expect(logger).
            to receive(:info).with(
              "<job_1> The latest possible version that can be installed is " \
              "1.2.0 because of the following conflicting dependency:\n" \
              "<job_1> \n" \
              "<job_1>   dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.2.0)"
            )

          updater.run
        end

        it "reports the correct error when there is no fixed version" do
          expect(checker).to receive(:lowest_resolvable_security_fix_version).
            and_return(nil)
          expect(checker).to receive(:lowest_security_fix_version).
            and_return(nil)
          expect(checker).to receive(:conflicting_dependencies).and_return([])

          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            1,
            {
              error_type: "security_update_not_possible",
              error_details: {
                "dependency-name": "dummy-pkg-b",
                "latest-resolvable-version": "1.1.0",
                "lowest-non-vulnerable-version": nil,
                "conflicting-dependencies": []
              }
            }
          )
          expect(logger).
            to receive(:info).with(
              "<job_1> The latest possible version of dummy-pkg-b that can be " \
              "installed is 1.1.0"
            )
          updater.run
        end
      end

      context "when the dependency is deemed up-to-date but still vulnerable" do
        it "doesn't update the dependency" do
          expect(checker).to receive(:up_to_date?).and_return(true)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).
            with(
              1,
              error_type: "security_update_not_found",
              error_details: {
                "dependency-name": "dummy-pkg-b",
                "dependency-version": "1.1.0"
              }
            )
          expect(logger).
            to receive(:info).
            with(
              "<job_1> Dependabot can't find a published or compatible " \
              "non-vulnerable version for dummy-pkg-b. " \
              "The latest available version is 1.1.0"
            )
          updater.run
        end
      end
    end

    context "when ignore conditions are set" do
      def expect_update_checker_with_ignored_versions(versions)
        expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
          dependency: anything,
          dependency_files: anything,
          repo_contents_path: anything,
          credentials: anything,
          ignored_versions: versions,
          security_advisories: anything,
          raise_on_ignored: anything,
          requirements_update_strategy: anything,
          options: anything
        ).once
      end

      describe "when ignores match the dependency name" do
        let(:requested_dependencies) { ["dummy-pkg-b"] }
        let(:ignore_conditions) { [{ "dependency-name" => "dummy-pkg-b", "version-requirement" => ">= 0" }] }

        it "passes ignored_versions to the update checker" do
          updater.run
          expect_update_checker_with_ignored_versions([">= 0"])
        end
      end

      describe "when all versions are ignored" do
        let(:ignore_conditions) do
          [
            { "dependency-name" => "dummy-pkg-a", "version-requirement" => "~> 2.0.0" },
            { "dependency-name" => "dummy-pkg-b", "version-requirement" => "~> 1.0.0" }
          ]
        end

        before do
          allow(checker).
            to receive(:latest_version).
            and_raise(Dependabot::AllVersionsIgnored)
          allow(checker).
            to receive(:up_to_date?).
            and_raise(Dependabot::AllVersionsIgnored)
        end

        it "logs the errors" do
          expect(logger).
            to receive(:info).
            with(
              "<job_1> All updates for dummy-pkg-a were ignored"
            )
          expect(logger).
            to receive(:info).
            with(
              "<job_1> All updates for dummy-pkg-b were ignored"
            )
          updater.run
        end

        it "doesn't report a job error" do
          updater.run
          expect(service).to_not have_received(:record_update_job_error)
        end
      end

      describe "without an ignore condition" do
        let(:requested_dependencies) { ["dummy-pkg-b"] }

        it "doesn't enable raised_on_ignore for ignore logging" do
          updater.run
          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: anything,
            dependency_files: anything,
            repo_contents_path: anything,
            credentials: anything,
            ignored_versions: anything,
            security_advisories: anything,
            raise_on_ignored: false,
            requirements_update_strategy: anything,
            options: anything
          )
        end
      end

      describe "with an ignored version" do
        let(:requested_dependencies) { ["dummy-pkg-b"] }
        let(:ignore_conditions) { [{ "dependency-name" => "dummy-pkg-b", "version-requirement" => "~> 1.0.0" }] }

        it "enables raised_on_ignore for ignore logging" do
          updater.run
          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: anything,
            dependency_files: anything,
            repo_contents_path: anything,
            credentials: anything,
            ignored_versions: anything,
            security_advisories: anything,
            raise_on_ignored: true,
            requirements_update_strategy: anything,
            options: anything
          )
        end
      end

      describe "with an ignored update-type" do
        let(:requested_dependencies) { ["dummy-pkg-b"] }
        let(:ignore_conditions) do
          [{ "dependency-name" => "dummy-pkg-b", "update-types" => ["version-update:semver-patch"] }]
        end

        it "enables raised_on_ignore for ignore logging" do
          updater.run
          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: anything,
            dependency_files: anything,
            repo_contents_path: anything,
            credentials: anything,
            ignored_versions: anything,
            security_advisories: anything,
            raise_on_ignored: true,
            requirements_update_strategy: anything,
            options: anything
          )
        end
      end

      describe "when ignores don't match the name" do
        let(:requested_dependencies) { ["dummy-pkg-a"] }
        let(:ignore_conditions) { [{ "dependency-name" => "dummy-pkg-b", "version-requirement" => ">= 0" }] }

        it "passes ignored_versions to the update checker" do
          updater.run
          expect_update_checker_with_ignored_versions([])
        end
      end

      describe "when ignores match a wildcard name" do
        let(:requested_dependencies) { ["dummy-pkg-a"] }
        let(:ignore_conditions) { [{ "dependency-name" => "dummy-pkg-*", "version-requirement" => ">= 0" }] }

        it "passes ignored_versions to the update checker" do
          updater.run
          expect_update_checker_with_ignored_versions([">= 0"])
        end
      end

      describe "when ignores define update-types with feature enabled" do
        let(:requested_dependencies) { ["dummy-pkg-b"] }
        let(:ignore_conditions) do
          [
            {
              "dependency-name" => "dummy-pkg-a",
              "version-requirement" => ">= 3.0.0, < 5"
            },
            {
              "dependency-name" => "dummy-pkg-*",
              "version-requirement" => ">= 2.0.0, < 3"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"]
            }
          ]
        end

        it "passes ignored_versions to the update checker" do
          updater.run
          expect_update_checker_with_ignored_versions([">= 2.0.0, < 3", "> 1.1.0, < 1.2", ">= 1.2.a, < 2"])
        end
      end
    end

    context "when cloning experiment is enabled" do
      let(:experiments) { { "cloning" => true } }

      it "passes the experiment to the FileUpdater" do
        expect(Dependabot::Bundler::FileUpdater).to receive(:new).with(
          dependencies: [dependency],
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials,
          options: { cloning: true }
        ).and_call_original
        expect(service).to receive(:create_pull_request).once
        updater.run
      end
    end

    it "updates the update config's dependency list" do
      job_id = 1
      dependencies = [
        {
          name: "dummy-pkg-a",
          version: "2.0.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 2.0.0",
              groups: [:default],
              source: nil
            }
          ]
        },
        {
          name: "dummy-pkg-b",
          version: "1.1.0",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.1.0",
              groups: [:default],
              source: nil
            }
          ]
        }
      ]
      dependency_files = ["/Gemfile", "/Gemfile.lock"]

      expect(service).
        to receive(:update_dependency_list).with(job_id, dependencies, dependency_files)
      updater.run
    end

    it "updates dependencies correctly" do
      job_id = 1
      dependencies = [have_attributes(name: "dummy-pkg-b")]
      updated_dependency_files = [
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
      base_commit_sha = "sha"
      pr_message = nil
      expect(service).
        to receive(:create_pull_request).
        with(job_id, dependencies, updated_dependency_files, base_commit_sha, pr_message)

      updater.run
    end

    it "builds pull request message" do
      expect(Dependabot::PullRequestCreator::MessageBuilder).
        to receive(:new).with(
          source: job.source,
          files: an_instance_of(Array),
          dependencies: an_instance_of(Array),
          credentials: credentials,
          commit_message_options: {
            include_scope: commit_message_include_scope,
            prefix: commit_message_prefix,
            prefix_development: commit_message_prefix_development
          },
          github_redirection_service: "github-redirect.dependabot.com"
        )
      updater.run
    end

    it "updates only the dependencies that need updating" do
      expect(service).to receive(:create_pull_request).once
      updater.run
    end

    context "when an update requires multiple dependencies to be updated" do
      before do
        allow(checker).
          to receive(:can_update?).with(requirements_to_unlock: :own).
          and_return(false, false)
        allow(checker).
          to receive(:can_update?).with(requirements_to_unlock: :all).
          and_return(false, true)
        allow(checker).to receive(:updated_dependencies).
          with(requirements_to_unlock: :all).
          and_return(multiple_dependencies)
      end

      let(:peer_checker) { double(Dependabot::Bundler::UpdateChecker) }
      before do
        allow(peer_checker).to receive(:can_update?).and_return(false)
        allow(Dependabot::Bundler::UpdateChecker).to receive(:new).
          and_return(checker, checker, peer_checker)
      end

      it "updates the dependency" do
        expect(service).to receive(:create_pull_request).once
        updater.run
      end

      context "when the peer dependency could update on its own" do
        before { allow(peer_checker).to receive(:can_update?).and_return(true) }

        it "doesn't update the dependency" do
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          updater.run
        end
      end

      context "with ignore conditions" do
        let(:ignore_conditions) do
          [
            { "dependency-name" => "dummy-pkg-a", "version-requirement" => "~> 2.0.0" },
            { "dependency-name" => "dummy-pkg-b", "version-requirement" => "~> 1.0.0" }
          ]
        end

        it "doesn't set raise_on_ignore for the peer_checker" do
          updater.run

          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: anything,
            dependency_files: anything,
            repo_contents_path: anything,
            credentials: anything,
            ignored_versions: anything,
            options: anything,
            security_advisories: anything,
            raise_on_ignored: true,
            requirements_update_strategy: anything
          ).twice.ordered
          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: anything,
            dependency_files: anything,
            repo_contents_path: anything,
            credentials: anything,
            ignored_versions: anything,
            options: anything,
            security_advisories: anything,
            raise_on_ignored: false,
            requirements_update_strategy: anything
          ).ordered
        end
      end
    end

    context "when a PR already exists" do
      let(:existing_pull_requests) do
        [
          [
            {
              "dependency-name" => "dummy-pkg-b",
              "dependency-version" => "1.2.0"
            }
          ]
        ]
      end

      context "for the latest version" do
        before do
          allow(checker).
            to receive(:latest_version).
            and_return(Gem::Version.new("1.2.0"))
        end

        it "doesn't call can_update? (so short-circuits resolution)" do
          expect(checker).to_not receive(:can_update?)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to_not receive(:record_update_job_error)
          expect(logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b " \
                 "with latest version 1.2.0")
          updater.run
        end
      end

      context "for the resolved version" do
        before do
          allow(checker).
            to receive(:latest_version).
            and_return(Gem::Version.new("1.3.0"))
        end

        it "doesn't update the dependency" do
          expect(checker).to receive(:up_to_date?).and_return(false, false)
          expect(checker).to receive(:can_update?).and_return(true, false)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to_not receive(:record_update_job_error)
          expect(logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b@1.2.0")
          updater.run
        end
      end

      context "when security only updates for the resolved version" do
        let(:security_updates_only) { true }
        let(:security_advisories) do
          [{ "dependency-name" => "dummy-pkg-b",
             "affected-versions" => ["1.1.0"] }]
        end

        before do
          allow(checker).
            to receive(:latest_version).
            and_return(Gem::Version.new("1.3.0"))
          allow(checker).to receive(:vulnerable?).and_return(true)
        end

        it "creates an update job error and short-circuits" do
          expect(checker).to receive(:up_to_date?).and_return(false)
          expect(checker).to receive(:can_update?).and_return(true)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).
            with(
              1,
              error_type: "pull_request_exists_for_security_update",
              error_details: {
                "updated-dependencies": [
                  "dependency-name": "dummy-pkg-b",
                  "dependency-version": "1.2.0"
                ]
              }
            )
          expect(logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b@1.2.0")
          updater.run
        end
      end

      context "when security only updates for the latest version" do
        let(:security_updates_only) { true }
        let(:security_advisories) do
          [{ "dependency-name" => "dummy-pkg-b",
             "affected-versions" => ["1.1.0"] }]
        end

        before do
          allow(checker).
            to receive(:latest_version).
            and_return(Gem::Version.new("1.2.0"))
          allow(checker).to receive(:vulnerable?).and_return(true)
        end

        it "doesn't call can_update? (so short-circuits resolution)" do
          expect(checker).to_not receive(:can_update?)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).
            with(
              1,
              error_type: "pull_request_exists_for_latest_version",
              error_details: {
                "dependency-name": "dummy-pkg-b",
                "dependency-version": "1.2.0"
              }
            )
          expect(logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b " \
                 "with latest version 1.2.0")
          updater.run
        end
      end

      context "for a different version" do
        let(:existing_pull_requests) do
          [
            {
              "dependency-name" => "dummy-pkg-b",
              "dependency-version" => "1.1.1"
            }
          ]
        end

        it "updates the dependency" do
          expect(service).to receive(:create_pull_request).once
          updater.run
        end
      end
    end

    context "when a PR already exists for a removed dependency" do
      let(:existing_pull_requests) do
        [
          [
            {
              "dependency-name" => "dummy-pkg-c",
              "dependency-version" => "1.4.0"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "dependency-removed" => true
            }
          ]
        ]
      end

      let(:security_updates_only) { true }
      let(:security_advisories) do
        [{ "dependency-name" => "dummy-pkg-b",
           "affected-versions" => ["1.1.0"] }]
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(Gem::Version.new("1.3.0"))
        allow(checker).to receive(:vulnerable?).and_return(true)
        allow(checker).to receive(:updated_dependencies).and_return([
          Dependabot::Dependency.new(
            name: "dummy-pkg-b",
            package_manager: "bundler",
            previous_version: "1.1.0",
            requirements: [],
            previous_requirements: [],
            removed: true
          ),
          Dependabot::Dependency.new(
            name: "dummy-pkg-c",
            package_manager: "bundler",
            version: "1.4.0",
            previous_version: "1.3.0",
            requirements: [
              { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
            ],
            previous_requirements: [
              { file: "Gemfile", requirement: "~> 1.3.0", groups: [], source: nil }
            ]
          )
        ])
      end

      it "creates an update job error and short-circuits" do
        expect(checker).to receive(:up_to_date?).and_return(false)
        expect(checker).to receive(:can_update?).and_return(true)
        expect(updater).to_not receive(:generate_dependency_files_for)
        expect(service).to_not receive(:create_pull_request)
        expect(service).to receive(:record_update_job_error).
          with(
            1,
            error_type: "pull_request_exists_for_security_update",
            error_details: {
              "updated-dependencies": [
                {
                  "dependency-name": "dummy-pkg-c",
                  "dependency-version": "1.4.0"
                },
                {
                  "dependency-name": "dummy-pkg-b",
                  "dependency-removed": true
                }
              ]
            }
          )
        expect(logger).
          to receive(:info).
          with("<job_1> Pull request already exists for dummy-pkg-c@1.4.0, dummy-pkg-b@removed")
        updater.run
      end
    end

    context "when a list of dependencies is specified" do
      let(:requested_dependencies) { ["dummy-pkg-b"] }

      context "and the job is to update a PR" do
        let(:updating_a_pull_request) { true }

        it "only attempts to update dependencies on the specified list" do
          expect(updater).
            to receive(:check_and_update_existing_pr_with_error_handling).
            and_call_original
          expect(updater).
            to_not receive(:check_and_create_pr_with_error_handling)
          expect(service).to receive(:create_pull_request).once

          updater.run
        end

        context "when security only updates" do
          let(:security_updates_only) { true }

          before do
            allow(checker).to receive(:vulnerable?).and_return(true)
          end

          context "the dependency isn't vulnerable" do
            it "closes the pull request" do
              expect(service).to receive(:close_pull_request).once
              updater.run
            end
          end

          context "the dependency is vulnerable" do
            let(:security_advisories) do
              [{ "dependency-name" => "dummy-pkg-b",
                 "affected-versions" => ["1.1.0"] }]
            end

            it "creates the pull request" do
              expect(service).to receive(:create_pull_request)
              updater.run
            end
          end

          context "the dependency is vulnerable but updates aren't allowed" do
            let(:security_advisories) do
              [{ "dependency-name" => "dummy-pkg-b",
                 "affected-versions" => ["1.1.0"] }]
            end
            let(:allowed_updates) do
              [
                {
                  "dependency-type" => "development"
                }
              ]
            end

            it "closes the pull request" do
              expect(service).to receive(:close_pull_request).once
              expect(logger).
                to receive(:info).with(
                  "<job_1> Dependency no longer allowed to update dummy-pkg-b 1.1.0"
                )
              updater.run
            end
          end
        end

        context "when the dependency doesn't appear in the parsed file" do
          let(:requested_dependencies) { ["removed_dependency"] }

          it "closes the pull request" do
            expect(service).to receive(:close_pull_request).once
            updater.run
          end

          context "because an error was raised parsing the dependencies" do
            before do
              allow(updater).to receive(:dependency_files).
                and_raise(
                  Dependabot::DependencyFileNotParseable.new("path/to/file")
                )
            end

            it "does not close the pull request" do
              expect(service).to_not receive(:close_pull_request)
              updater.run
            end
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          let(:requested_dependencies) { ["Dummy-pkg-b"] }

          it "only attempts to update dependencies on the specified list" do
            expect(updater).
              to receive(:check_and_update_existing_pr_with_error_handling).
              and_call_original
            expect(updater).
              to_not receive(:check_and_create_pr_with_error_handling)
            expect(service).to receive(:create_pull_request).once
            expect(service).not_to receive(:close_pull_request)

            updater.run
          end
        end

        context "when a PR already exists" do
          let(:existing_pull_requests) do
            [
              [
                {
                  "dependency-name" => "dummy-pkg-b",
                  "dependency-version" => "1.2.0"
                }
              ]
            ]
          end

          it "updates the dependency" do
            expect(service).to receive(:update_pull_request).once
            updater.run
          end

          context "for a different version" do
            let(:existing_pull_requests) do
              [
                [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "dependency-version" => "1.1.1"
                  }
                ]
              ]
            end

            it "updates the dependency" do
              expect(service).to receive(:create_pull_request).once
              updater.run
            end
          end
        end

        context "when the dependency no-longer needs updating" do
          before { allow(checker).to receive(:can_update?).and_return(false) }

          it "closes the pull request" do
            expect(service).to receive(:close_pull_request).once
            updater.run
          end
        end
      end

      context "and the job is not to update a PR" do
        let(:updating_a_pull_request) { false }

        it "only attempts to update dependencies on the specified list" do
          expect(updater).
            to receive(:check_and_create_pr_with_error_handling).
            and_call_original
          expect(updater).
            to_not receive(:check_and_update_existing_pr_with_error_handling)
          expect(service).to receive(:create_pull_request).once

          updater.run
        end

        context "when the dependency doesn't appear in the parsed file" do
          let(:requested_dependencies) { ["removed_dependency"] }

          it "does not try to close any pull request" do
            expect(service).to_not receive(:close_pull_request)
            updater.run
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          let(:requested_dependencies) { ["Dummy-pkg-b"] }

          it "only attempts to update dependencies on the specified list" do
            expect(updater).
              to receive(:check_and_create_pr_with_error_handling).
              and_call_original
            expect(updater).
              to_not receive(:check_and_update_existing_pr_with_error_handling)
            expect(service).to receive(:create_pull_request).once

            updater.run
          end
        end

        context "when the dependency is a sub-dependency" do
          let(:requested_dependencies) { ["dummy-pkg-a"] }

          let(:dependency_files) do
            [
              Dependabot::DependencyFile.new(
                name: "Gemfile",
                content: fixture("bundler/original/sub_dep"),
                directory: "/"
              ),
              Dependabot::DependencyFile.new(
                name: "Gemfile.lock",
                content: fixture("bundler/original/sub_dep.lock"),
                directory: "/"
              )
            ]
          end

          it "still attempts to update the dependency" do
            expect(updater).
              to receive(:check_and_create_pr_with_error_handling).
              and_call_original
            expect(updater).
              to_not receive(:check_and_update_existing_pr_with_error_handling)
            expect(service).to receive(:create_pull_request).once

            updater.run
          end
        end

        context "for security only updates" do
          let(:security_updates_only) { true }

          before do
            allow(checker).to receive(:vulnerable?).and_return(true)
          end

          context "when the dependency is vulnerable" do
            let(:security_advisories) do
              [{ "dependency-name" => "dummy-pkg-b",
                 "affected-versions" => ["1.1.0"] }]
            end

            it "creates the pull request" do
              expect(service).to receive(:create_pull_request)
              updater.run
            end
          end

          context "when the dependency is not allowed to update" do
            let(:security_advisories) do
              [{ "dependency-name" => "dummy-pkg-b",
                 "affected-versions" => ["1.1.0"] }]
            end
            let(:allowed_updates) do
              [
                {
                  "dependency-type" => "development"
                }
              ]
            end

            it "does not create the pull request" do
              expect(service).not_to receive(:create_pull_request)
              expect(service).to receive(:record_update_job_error).with(
                1,
                {
                  error_type: "all_versions_ignored",
                  error_details: {
                    "dependency-name": "dummy-pkg-b"
                  }
                }
              )
              expect(logger).
                to receive(:info).with(
                  "<job_1> Dependabot cannot update to the required version as all " \
                  "versions were ignored for dummy-pkg-b"
                )
              updater.run
            end
          end

          context "when the dependency is no longer vulnerable" do
            let(:security_advisories) do
              [{ "dependency-name" => "dummy-pkg-b",
                 "affected-versions" => ["1.0.0"],
                 "patched-versions" => ["1.1.0"] }]
            end

            before do
              allow(checker).to receive(:vulnerable?).and_return(false)
            end

            it "does not create pull request" do
              expect(service).to_not receive(:create_pull_request)
              expect(service).to receive(:record_update_job_error).with(
                1,
                {
                  error_type: "security_update_not_needed",
                  error_details: {
                    "dependency-name": "dummy-pkg-b"
                  }
                }
              )
              expect(logger).
                to receive(:info).with(
                  "<job_1> no security update needed as dummy-pkg-b " \
                  "is no longer vulnerable"
                )

              updater.run
            end
          end
        end
      end
    end

    context "when an error is raised" do
      let(:error) { StandardError }

      before do
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }
      end

      context "during parsing" do
        before { allow(updater).to receive(:dependency_files).and_raise(error) }

        context "and it's an unknown error" do
          let(:error) { StandardError.new("hell") }

          it "tells Sentry" do
            expect(Raven).to receive(:capture_exception)
            updater.run
          end

          it "tells the main backend" do
            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "unknown_error",
                error_details: nil
              )
            updater.run
          end
        end

        context "but it's a Dependabot::DependencyFileNotFound" do
          let(:error) { Dependabot::DependencyFileNotFound.new("path/to/file") }

          it "doesn't tell Sentry" do
            expect(Raven).to_not receive(:capture_exception)
            updater.run
          end

          it "tells the main backend" do
            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "dependency_file_not_found",
                error_details: { "file-path": "path/to/file" }
              )
            updater.run
          end
        end

        context "but it's a Dependabot::BranchNotFound" do
          let(:error) { Dependabot::BranchNotFound.new("my_branch") }

          it "doesn't tell Sentry" do
            expect(Raven).to_not receive(:capture_exception)
            updater.run
          end

          it "tells the main backend" do
            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "branch_not_found",
                error_details: { "branch-name": "my_branch" }
              )
            updater.run
          end
        end

        context "but it's a Dependabot::DependencyFileNotParseable" do
          let(:error) do
            Dependabot::DependencyFileNotParseable.new("path/to/file", "a")
          end

          it "doesn't tell Sentry" do
            expect(Raven).to_not receive(:capture_exception)
            updater.run
          end

          it "tells the main backend" do
            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "dependency_file_not_parseable",
                error_details: { "file-path": "path/to/file", message: "a" }
              )
            updater.run
          end
        end

        context "but it's a Dependabot::PathDependenciesNotReachable" do
          let(:error) do
            Dependabot::PathDependenciesNotReachable.new(["bad_gem"])
          end

          it "doesn't tell Sentry" do
            expect(Raven).to_not receive(:capture_exception)
            updater.run
          end

          it "tells the main backend" do
            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "path_dependencies_not_reachable",
                error_details: { dependencies: ["bad_gem"] }
              )
            updater.run
          end
        end
      end

      context "but it's a Dependabot::DependencyFileNotResolvable" do
        let(:error) { Dependabot::DependencyFileNotResolvable.new("message") }

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "dependency_file_not_resolvable",
              error_details: { message: "message" }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::DependencyFileNotEvaluatable" do
        let(:error) { Dependabot::DependencyFileNotEvaluatable.new("message") }

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "dependency_file_not_evaluatable",
              error_details: { message: "message" }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::InconsistentRegistryResponse" do
        let(:error) { Dependabot::InconsistentRegistryResponse.new("message") }

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "doesn't tell the main backend" do
          expect(service).to_not receive(:record_update_job_error)
          updater.run
        end
      end

      context "but it's a Dependabot::GitDependenciesNotReachable" do
        let(:error) do
          Dependabot::GitDependenciesNotReachable.new("https://example.com")
        end

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "git_dependencies_not_reachable",
              error_details: { "dependency-urls": ["https://example.com"] }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::GitDependencyReferenceNotFound" do
        let(:error) do
          Dependabot::GitDependencyReferenceNotFound.new("some_dep")
        end

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "git_dependency_reference_not_found",
              error_details: { dependency: "some_dep" }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::GoModulePathMismatch" do
        let(:error) do
          Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
        end

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "go_module_path_mismatch",
              error_details: {
                "declared-path": "foo",
                "discovered-path": "bar",
                "go-mod": "/go.mod"
              }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::PrivateSourceAuthenticationFailure" do
        let(:error) do
          Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
        end

        it "doesn't tell Sentry" do
          expect(Raven).to_not receive(:capture_exception)
          updater.run
        end

        it "tells the main backend" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "private_source_authentication_failure",
              error_details: { source: "some.example.com" }
            )
          updater.run
        end
      end

      context "but it's a Dependabot::SharedHelpers::HelperSubprocessFailed" do
        let(:error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "Potentially sensitive log content goes here",
            error_context: {}
          )
        end

        it "tells the main backend there has been an unknown error" do
          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "unknown_error",
              error_details: nil
            )
          updater.run
        end

        it "notifies Sentry with a breadcrumb to check the logs" do
          expect(Raven).
            to receive(:capture_exception).
            with(instance_of(Dependabot::Updater::SubprocessFailed), anything)
          updater.run
        end
      end

      it "tells Sentry" do
        expect(Raven).to receive(:capture_exception).once
        updater.run
      end

      it "tells the main backend" do
        expect(service).
          to receive(:record_update_job_error).
          with(
            1,
            error_type: "unknown_error",
            error_details: nil
          )
        updater.run
      end

      it "still processes the other jobs" do
        expect(service).to receive(:create_pull_request).once
        updater.run
      end
    end

    describe "experiments" do
      let(:experiments) do
        { "large-hadron-collider" => true }
      end

      it "passes the experiments to the FileParser as options" do
        expect(Dependabot::Bundler::FileParser).to receive(:new).with(
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          source: job.source,
          credentials: credentials,
          reject_external_code: job.reject_external_code?,
          options: { large_hadron_collider: true }
        ).and_call_original

        updater.run
      end

      it "passes the experiments to the FileUpdater as options" do
        expect(Dependabot::Bundler::FileUpdater).to receive(:new).with(
          dependencies: [dependency],
          dependency_files: dependency_files,
          repo_contents_path: repo_contents_path,
          credentials: credentials,
          options: { large_hadron_collider: true }
        ).and_call_original

        updater.run
      end

      it "passes the experiments to the UpdateChecker as options" do
        updater.run

        expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
          dependency: anything,
          dependency_files: anything,
          repo_contents_path: anything,
          credentials: anything,
          ignored_versions: anything,
          security_advisories: anything,
          raise_on_ignored: anything,
          requirements_update_strategy: anything,
          options: { large_hadron_collider: true }
        ).twice
      end

      context "with a bundler 2 project" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("bundler2/original/Gemfile"),
              directory: "/"
            ),
            Dependabot::DependencyFile.new(
              name: "Gemfile.lock",
              content: fixture("bundler2/original/Gemfile.lock"),
              directory: "/"
            )
          ]
        end

        it "updates dependencies correctly" do
          job_id = 1
          dependencies = [have_attributes(name: "dummy-pkg-b")]
          updated_dependency_files = [
            {
              "name" => "Gemfile",
              "content" => fixture("bundler2/updated/Gemfile"),
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
              "content" => fixture("bundler2/updated/Gemfile.lock"),
              "directory" => "/",
              "type" => "file",
              "mode" => "100644",
              "support_file" => false,
              "content_encoding" => "utf-8",
              "deleted" => false,
              "operation" => "update"
            }
          ]
          base_commit_sha = "sha"
          pr_message = nil
          expect(service).
            to receive(:create_pull_request).
            with(job_id, dependencies, updated_dependency_files, base_commit_sha, pr_message)

          updater.run
        end
      end
    end

    it "does not log empty ignore conditions" do
      expect(logger).
        not_to receive(:info).
        with(/Ignored versions:/)
      updater.run
    end

    context "with ignore conditions" do
      let(:config_ignore_condition) do
        {
          "dependency-name" => "*-pkg-b",
          "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
          "source" => ".github/dependabot.yaml"
        }
      end
      let(:comment_ignore_condition) do
        {
          "dependency-name" => dependency.name,
          "version-requirement" => ">= 1.a, < 2.0.0",
          "source" => "@dependabot ignore command"
        }
      end
      let(:ignore_conditions) { [config_ignore_condition, comment_ignore_condition] }

      it "logs ignored versions" do
        updater.run
        expect(logger).
          to have_received(:info).
          with(/Ignored versions:/)
      end

      it "logs ignore conditions" do
        updater.run
        expect(logger).
          to have_received(:info).
          with("<job_1>   >= 1.a, < 2.0.0 - from @dependabot ignore command")
      end

      it "logs ignored update types" do
        updater.run
        expect(logger).
          to have_received(:info).
          with("<job_1>   version-update:semver-patch - from .github/dependabot.yaml")
        expect(logger).
          to have_received(:info).
          with("<job_1>   version-update:semver-minor - from .github/dependabot.yaml")
      end
    end

    context "with ignored versions that don't apply during a security update" do
      let(:security_updates_only) { true }
      let(:requested_dependencies) { ["dummy-pkg-b"] }
      let(:ignore_conditions) do
        [
          {
            "dependency-name" => "dummy-pkg-b",
            "update-types" => ["version-update:semver-patch"],
            "source" => ".github/dependabot.yaml"
          }
        ]
      end

      it "logs ignored versions" do
        updater.run
        expect(logger).
          to have_received(:info).
          with(/Ignored versions:/)
      end

      it "logs ignored update types" do
        updater.run
        expect(logger).
          to have_received(:info).
          with(
            "<job_1>   version-update:semver-patch - from .github/dependabot.yaml (doesn't apply to security update)"
          )
      end
    end
  end
end
