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
  # rubocop:disable Metrics/MethodLength
  def build_job(requested_dependencies: nil, allowed_updates: default_allowed_updates,
                existing_pull_requests: [], ignore_conditions: [], security_advisories: [],
                experiments: {}, updating_a_pull_request: false, security_updates_only: false)
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
      credentials: [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        },
        {
          "type" => "random",
          "secret" => "codes"
        }
      ],
      lockfile_only: false,
      requirements_update_strategy: nil,
      update_subdependencies: false,
      updating_a_pull_request: updating_a_pull_request,
      vendor_dependencies: false,
      experiments: experiments,
      commit_message_options: {
        "prefix" => "[bump]",
        "prefix-development" => "[bump-dev]",
        "include-scope" => true
      },
      security_updates_only: security_updates_only
    )
  end
  # rubocop:enable Metrics/MethodLength

  def build_updater(service: build_service, job: build_job, dependency_files: default_dependency_files)
    Dependabot::Updater.new(
      service: service,
      job_id: 1,
      job: job,
      dependency_files: dependency_files,
      base_commit_sha: "sha",
      repo_contents_path: nil
    )
  end

  def build_service(job: build_job)
    instance_double(
      Dependabot::Service,
      get_job: job,
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      mark_job_as_processed: nil,
      update_dependency_list: nil,
      record_update_job_error: nil
    )
  end

  def default_dependency_files
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

  def default_allowed_updates
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

  before do
    allow(Dependabot.logger).to receive(:info)
    allow(Dependabot.logger).to receive(:error)

    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("rubygems-index"))
    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-a").
      to_return(status: 200, body: fixture("rubygems-info-a"))
    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-b").
      to_return(status: 200, body: fixture("rubygems-info-b"))
  end

  # rubocop:disable Metrics/MethodLength
  def stub_update_checker(stubs = {})
    update_checker =
      instance_double(
        Dependabot::Bundler::UpdateChecker,
        {
          up_to_date?: false,
          vulnerable?: false,
          version_class: Dependabot::Bundler::Version,
          latest_version: Gem::Version.new("1.2.0"),
          dependency: Dependabot::Dependency.new(
            name: "dummy-pkg-b",
            package_manager: "bundler",
            version: "1.1.0",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.1.0",
                groups: [],
                source: nil
              }
            ]
          ),
          updated_dependencies: [
            Dependabot::Dependency.new(
              name: "dummy-pkg-b",
              package_manager: "bundler",
              version: "1.2.0",
              previous_version: "1.1.0",
              requirements: [
                {
                  file: "Gemfile",
                  requirement: "~> 1.2.0",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "Gemfile",
                  requirement: "~> 1.1.0",
                  groups: [],
                  source: nil
                }
              ]
            )
          ]
        }.merge(stubs)
      )

    allow(Dependabot::Bundler::UpdateChecker).to receive(:new).and_return(update_checker)
    allow(update_checker).to receive(:requirements_unlocked_or_can_be?).and_return(true)
    allow(update_checker).to receive(:can_update?).with(requirements_to_unlock: :own).and_return(true, false)
    allow(update_checker).to receive(:can_update?).with(requirements_to_unlock: :all).and_return(false)
    update_checker
  end
  # rubocop:enable Metrics/MethodLength

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

  describe "#run" do
    context "when the host is out of disk space" do
      it "records an 'out_of_disk' error" do
        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        allow(job).to receive(:updating_a_pull_request?).and_raise(Errno::ENOSPC)

        updater.run

        expect(service).to have_received(:record_update_job_error).
          with(anything, { error_type: "out_of_disk", error_details: nil, dependency: nil })
      end
    end

    context "when github pr creation is rate limiting" do
      before do
        error = Octokit::TooManyRequests.new({
          status: 403,
          response_headers: { "X-RateLimit-Reset" => 42 }
        })
        message_builder = double(Dependabot::PullRequestCreator::MessageBuilder)
        allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder)
        allow(message_builder).to receive(:message).and_raise(error)
      end

      it "records an 'octokit_rate_limited' error" do
        stub_update_checker

        job = build_job(
          experiments: {
            "build-pull-request-message" => true
          }
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(service).to have_received(:record_update_job_error).
          with(
            anything,
            {
              error_type: "octokit_rate_limited",
              error_details: { "rate-limit-reset": 42 },
              dependency: an_instance_of(Dependabot::Dependency)
            }
          )
      end
    end

    context "when the job has already been processed" do
      it "no-ops" do
        job = nil
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(updater).to_not receive(:dependencies)

        updater.run
      end
    end

    it "logs the current and latest versions" do
      stub_update_checker

      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

      expect(Dependabot.logger).
        to receive(:info).
        with("<job_1> Checking if dummy-pkg-b 1.1.0 needs updating")
      expect(Dependabot.logger).
        to receive(:info).
        with("<job_1> Latest version is 1.2.0")

      updater.run
    end

    context "when the checker has an requirements update strategy" do
      it "logs the update requirements and strategy" do
        stub_update_checker(requirements_update_strategy: :bump_versions)

        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Dependabot.logger).
          to receive(:info).
          with("<job_1> Requirements to unlock own")
        expect(Dependabot.logger).
          to receive(:info).
          with("<job_1> Requirements update strategy bump_versions")

        updater.run
      end
    end

    context "when no dependencies are allowed" do
      it "logs the current and latest versions" do
        job = build_job(
          allowed_updates: [
            {
              "dependency-name" => "typoed-dep-name"
            }
          ]
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Dependabot.logger).
          to receive(:info).
          with("<job_1> Found no dependencies to update after filtering " \
               "allowed updates")
        updater.run
      end
    end

    context "for security only updates" do
      it "creates the pull request" do
        stub_update_checker(vulnerable?: true)

        job = build_job(
          security_advisories: [
            {
              "dependency-name" => "dummy-pkg-b",
              "affected-versions" => ["1.1.0"],
              "patched-versions" => ["1.2.0"]
            }
          ],
          security_updates_only: true
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end

      context "when the dep has no version so we can't check vulnerability" do
        it "does not create pull request" do
          stub_update_checker(
            dependency: Dependabot::Dependency.new(
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
          )

          job = build_job(
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"],
                "patched-versions" => ["1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).to_not receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            1,
            {
              error_type: "dependency_file_not_supported",
              error_details: {
                "dependency-name": "dummy-pkg-b"
              },
              dependency: nil
            }
          )
          expect(Dependabot.logger).
            to receive(:info).with(
              "<job_1> Dependabot can't update vulnerable dependencies for " \
              "projects without a lockfile or pinned version requirement as " \
              "the currently installed version of dummy-pkg-b isn't known."
            )

          updater.run
        end
      end

      context "when the dependency is no longer vulnerable" do
        it "does not create pull request" do
          job = build_job(
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"],
                "patched-versions" => ["1.1.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).to_not receive(:create_pull_request)

          updater.run
        end
      end

      context "when the update is still vulnerable" do
        it "does not create pull request" do
          checker = stub_update_checker(vulnerable?: true)

          job = build_job(
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0", "1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
              },
              dependency: nil
            }
          )
          expect(Dependabot.logger).
            to receive(:info).with(
              "<job_1> The latest possible version that can be installed is " \
              "1.2.0 because of the following conflicting dependency:\n" \
              "<job_1> \n" \
              "<job_1>   dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.2.0)"
            )

          updater.run
        end

        it "reports the correct error when there is no fixed version" do
          checker = stub_update_checker(vulnerable?: true)

          job = build_job(
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0", "1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
              },
              dependency: nil
            }
          )
          expect(Dependabot.logger).
            to receive(:info).with(
              "<job_1> The latest possible version of dummy-pkg-b that can be " \
              "installed is 1.1.0"
            )

          updater.run
        end
      end

      context "when the dependency is deemed up-to-date but still vulnerable" do
        it "doesn't update the dependency" do
          checker = stub_update_checker(vulnerable?: true, up_to_date?: true)

          job = build_job(
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0", "1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
              },
              dependency: an_instance_of(Dependabot::Dependency)
            )
          expect(Dependabot.logger).
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
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => ">= 0"
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          updater.run
          expect_update_checker_with_ignored_versions([">= 0"])
        end
      end

      describe "when all versions are ignored" do
        it "logs the errors" do
          checker = stub_update_checker
          allow(checker).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
          allow(checker).to receive(:up_to_date?).and_raise(Dependabot::AllVersionsIgnored)

          ignore_conditions = [
            { "dependency-name" => "dummy-pkg-a", "version-requirement" => "~> 2.0.0" },
            { "dependency-name" => "dummy-pkg-b", "version-requirement" => "~> 1.0.0" }
          ]
          job = build_job(ignore_conditions: ignore_conditions)
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Dependabot.logger).
            to receive(:info).
            with(
              "<job_1> All updates for dummy-pkg-a were ignored"
            )
          expect(Dependabot.logger).
            to receive(:info).
            with(
              "<job_1> All updates for dummy-pkg-b were ignored"
            )

          updater.run
        end

        it "doesn't report a job error" do
          checker = stub_update_checker
          allow(checker).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
          allow(checker).to receive(:up_to_date?).and_raise(Dependabot::AllVersionsIgnored)

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          updater.run

          expect(service).to_not have_received(:record_update_job_error)
        end
      end

      describe "without an ignore condition" do
        it "doesn't enable raised_on_ignore for ignore logging" do
          stub_update_checker

          job = build_job(requested_dependencies: ["dummy-pkg-b"])
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
        it "enables raised_on_ignore for ignore logging" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => "~> 1.0.0"
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
        it "enables raised_on_ignore for ignore logging" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "update-types" => ["version-update:semver-patch"]
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-a"],
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => ">= 0"
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions([])
        end
      end

      describe "when ignores match a wildcard name" do
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-a"],
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-*",
                "version-requirement" => ">= 0"
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions([">= 0"])
        end
      end

      describe "when ignores define update-types with feature enabled" do
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            ignore_conditions: [
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
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions([">= 2.0.0, < 3", "> 1.1.0, < 1.2", ">= 1.2.a, < 2"])
        end
      end
    end

    context "when cloning experiment is enabled" do
      it "passes the experiment to the FileUpdater" do
        stub_update_checker

        job = build_job(experiments: { "cloning" => true })
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Dependabot::Bundler::FileUpdater).to receive(:new).with(
          dependencies: [
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
          ],
          dependency_files: default_dependency_files,
          repo_contents_path: nil,
          credentials: [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "github-token"
            },
            { "type" => "random", "secret" => "codes" }
          ],
          options: { cloning: true }
        ).and_call_original

        expect(service).to receive(:create_pull_request).once

        updater.run
      end
    end

    it "updates the update config's dependency list" do
      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

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

    # FIXME: This spec fails (when run outside Dockerfile.updater-core) because mode is being changed to 100666
    it "updates dependencies correctly" do
      stub_update_checker

      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

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
      stub_update_checker

      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

      expect(Dependabot::PullRequestCreator::MessageBuilder).
        to receive(:new).with(
          source: job.source,
          files: an_instance_of(Array),
          dependencies: an_instance_of(Array),
          credentials: [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "github-token"
            },
            { "type" => "random", "secret" => "codes" }
          ],
          commit_message_options: {
            include_scope: true,
            prefix: "[bump]",
            prefix_development: "[bump-dev]"
          },
          github_redirection_service: "github-redirect.dependabot.com"
        )

      updater.run
    end

    it "updates only the dependencies that need updating" do
      stub_update_checker

      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

      expect(service).to receive(:create_pull_request).once

      updater.run
    end

    context "when an update requires multiple dependencies to be updated" do
      it "updates the dependency" do
        checker = stub_update_checker
        allow(checker).
          to receive(:can_update?).with(requirements_to_unlock: :own).
          and_return(false, false)
        allow(checker).
          to receive(:can_update?).with(requirements_to_unlock: :all).
          and_return(false, true)

        peer_checker = stub_update_checker(can_update?: false)
        allow(Dependabot::Bundler::UpdateChecker).to receive(:new).
          and_return(checker, checker, peer_checker)

        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end

      context "when the peer dependency could update on its own" do
        it "doesn't update the dependency" do
          checker = stub_update_checker
          allow(checker).
            to receive(:can_update?).with(requirements_to_unlock: :own).
            and_return(false, false)
          allow(checker).
            to receive(:can_update?).with(requirements_to_unlock: :all).
            and_return(false, true)
          allow(checker).to receive(:updated_dependencies).
            with(requirements_to_unlock: :all).
            and_return(
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
            )
          peer_checker = stub_update_checker(can_update?: true)
          allow(Dependabot::Bundler::UpdateChecker).to receive(:new).
            and_return(checker, checker, peer_checker)

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)

          updater.run
        end
      end

      context "with ignore conditions" do
        it "doesn't set raise_on_ignore for the peer_checker" do
          checker = stub_update_checker
          allow(checker).
            to receive(:can_update?).with(requirements_to_unlock: :own).
            and_return(false, false)
          allow(checker).
            to receive(:can_update?).with(requirements_to_unlock: :all).
            and_return(false, true)
          allow(checker).to receive(:updated_dependencies).
            with(requirements_to_unlock: :all).
            and_return(
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
            )

          job = build_job(ignore_conditions: [
            {
              "dependency-name" => "dummy-pkg-a",
              "version-requirement" => "~> 2.0.0"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "version-requirement" => "~> 1.0.0"
            }
          ])
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
          # this is the "peer checker" instantiation
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
      context "for the latest version" do
        it "doesn't call can_update? (so short-circuits resolution)" do
          checker = stub_update_checker

          job = build_job(existing_pull_requests: [
            [
              {
                "dependency-name" => "dummy-pkg-b",
                "dependency-version" => "1.2.0"
              }
            ]
          ])
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(checker).to_not receive(:can_update?)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to_not receive(:record_update_job_error)
          expect(Dependabot.logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b " \
                 "with latest version 1.2.0")

          updater.run
        end
      end

      context "for the resolved version" do
        it "doesn't update the dependency" do
          checker = stub_update_checker(latest_version: Gem::Version.new("1.3.0"))

          job = build_job(existing_pull_requests: [
            [
              {
                "dependency-name" => "dummy-pkg-b",
                "dependency-version" => "1.2.0"
              }
            ]
          ])
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(checker).to receive(:up_to_date?).and_return(false, false)
          expect(checker).to receive(:can_update?).and_return(true, false)
          expect(updater).to_not receive(:generate_dependency_files_for)
          expect(service).to_not receive(:create_pull_request)
          expect(service).to_not receive(:record_update_job_error)
          expect(Dependabot.logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b@1.2.0")

          updater.run
        end
      end

      context "when security only updates for the resolved version" do
        it "creates an update job error and short-circuits" do
          checker = stub_update_checker(latest_version: Gem::Version.new("1.3.0"), vulnerable?: true)

          job = build_job(
            existing_pull_requests: [
              [
                {
                  "dependency-name" => "dummy-pkg-b",
                  "dependency-version" => "1.2.0"
                }
              ]
            ],
            security_updates_only: true,
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"]
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
              },
              dependency: nil
            )
          expect(Dependabot.logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b@1.2.0")

          updater.run
        end
      end

      context "when security only updates for the latest version" do
        it "doesn't call can_update? (so short-circuits resolution)" do
          checker = stub_update_checker(vulnerable?: true)

          job = build_job(
            existing_pull_requests: [
              [
                {
                  "dependency-name" => "dummy-pkg-b",
                  "dependency-version" => "1.2.0"
                }
              ]
            ],
            security_updates_only: true,
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"]
              }
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

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
              },
              dependency: an_instance_of(Dependabot::Dependency)
            )
          expect(Dependabot.logger).
            to receive(:info).
            with("<job_1> Pull request already exists for dummy-pkg-b " \
                 "with latest version 1.2.0")

          updater.run
        end
      end

      context "for a different version" do
        it "updates the dependency" do
          stub_update_checker

          job = build_job(
            existing_pull_requests: [
              [
                {
                  "dependency-name" => "dummy-pkg-b",
                  "dependency-version" => "1.1.1"
                }
              ]
            ]
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).to receive(:create_pull_request).once

          updater.run
        end
      end
    end

    context "when a PR already exists for a removed dependency" do
      it "creates an update job error and short-circuits" do
        checker =
          stub_update_checker(
            latest_version: Gem::Version.new("1.3.0"),
            vulnerable?: true,
            updated_dependencies: [
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
            ]
          )

        job = build_job(
          existing_pull_requests: [
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
          ],
          security_updates_only: true,
          security_advisories: [
            {
              "dependency-name" => "dummy-pkg-b",
              "affected-versions" => ["1.1.0"]
            }
          ]
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

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
            },
            dependency: nil
          )
        expect(Dependabot.logger).
          to receive(:info).
          with("<job_1> Pull request already exists for dummy-pkg-c@1.4.0, dummy-pkg-b@removed")
        updater.run
      end
    end

    context "when a list of dependencies is specified" do
      context "and the job is to update a PR" do
        it "only attempts to update dependencies on the specified list" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            updating_a_pull_request: true
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(updater).
            to receive(:check_and_update_existing_pr_with_error_handling).
            and_call_original
          expect(updater).
            to_not receive(:check_and_create_pr_with_error_handling)
          expect(service).to receive(:create_pull_request).once

          updater.run
        end

        context "when security only updates" do
          context "the dependency isn't vulnerable" do
            it "closes the pull request" do
              stub_update_checker(vulnerable?: true)

              job = build_job(
                security_updates_only: true,
                requested_dependencies: ["dummy-pkg-b"],
                updating_a_pull_request: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to receive(:close_pull_request).once

              updater.run
            end
          end

          context "the dependency is vulnerable" do
            it "creates the pull request" do
              stub_update_checker(vulnerable?: true)

              job = build_job(
                security_updates_only: true,
                requested_dependencies: ["dummy-pkg-b"],
                security_advisories: [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "affected-versions" => ["1.1.0"]
                  }
                ],
                updating_a_pull_request: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to receive(:create_pull_request)

              updater.run
            end
          end

          context "the dependency is vulnerable but updates aren't allowed" do
            it "closes the pull request" do
              stub_update_checker(vulnerable?: true)

              job = build_job(
                security_updates_only: true,
                requested_dependencies: ["dummy-pkg-b"],
                security_advisories: [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "affected-versions" => ["1.1.0"]
                  }
                ],
                allowed_updates: [
                  {
                    "dependency-type" => "development"
                  }
                ],
                updating_a_pull_request: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to receive(:close_pull_request).once
              expect(Dependabot.logger).
                to receive(:info).with(
                  "<job_1> Dependency no longer allowed to update dummy-pkg-b 1.1.0"
                )

              updater.run
            end
          end
        end

        context "when the dependency doesn't appear in the parsed file" do
          it "closes the pull request" do
            job = build_job(
              requested_dependencies: ["removed_dependency"],
              updating_a_pull_request: true
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once

            updater.run
          end

          context "because an error was raised parsing the dependencies" do
            it "does not close the pull request" do
              job = build_job(
                requested_dependencies: ["removed_dependency"],
                updating_a_pull_request: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              allow(updater).to receive(:dependency_files).
                and_raise(Dependabot::DependencyFileNotParseable.new("path/to/file"))

              expect(service).to_not receive(:close_pull_request)

              updater.run
            end
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          it "only attempts to update dependencies on the specified list" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["Dummy-pkg-b"],
              updating_a_pull_request: true
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

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
          it "updates the dependency" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["Dummy-pkg-b"],
              existing_pull_requests: [
                [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "dependency-version" => "1.2.0"
                  }
                ]
              ],
              updating_a_pull_request: true
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:update_pull_request).once

            updater.run
          end

          context "for a different version" do
            it "updates the dependency" do
              stub_update_checker

              job = build_job(
                requested_dependencies: ["Dummy-pkg-b"],
                existing_pull_requests: [
                  [
                    {
                      "dependency-name" => "dummy-pkg-b",
                      "dependency-version" => "1.1.1"
                    }
                  ]
                ],
                updating_a_pull_request: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to receive(:create_pull_request).once

              updater.run
            end
          end
        end

        context "when the dependency no-longer needs updating" do
          it "closes the pull request" do
            checker = stub_update_checker
            allow(checker).to receive(:can_update?).and_return(false)

            job = build_job(
              requested_dependencies: ["dummy-pkg-b"],
              updating_a_pull_request: true
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once

            updater.run
          end
        end
      end

      context "and the job is not to update a PR" do
        it "only attempts to update dependencies on the specified list" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            updating_a_pull_request: false
          )
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(updater).
            to receive(:check_and_create_pr_with_error_handling).
            and_call_original
          expect(updater).
            to_not receive(:check_and_update_existing_pr_with_error_handling)
          expect(service).to receive(:create_pull_request).once

          updater.run
        end

        context "when the dependency doesn't appear in the parsed file" do
          it "does not try to close any pull request" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["removed_dependency"],
              updating_a_pull_request: false
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            expect(service).to_not receive(:close_pull_request)

            updater.run
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          it "only attempts to update dependencies on the specified list" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["Dummy-pkg-b"],
              updating_a_pull_request: false
            )
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

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
          it "still attempts to update the dependency" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["dummy-pkg-a"],
              updating_a_pull_request: false
            )
            service = build_service(job: job)
            updater = build_updater(
              service: service,
              job: job,
              dependency_files: [
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
            )

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
          context "when the dependency is vulnerable" do
            it "creates the pull request" do
              stub_update_checker(vulnerable?: true)

              job = build_job(
                requested_dependencies: ["dummy-pkg-b"],
                security_advisories: [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "affected-versions" => ["1.1.0"]
                  }
                ],
                security_updates_only: true,
                updating_a_pull_request: false
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to receive(:create_pull_request)

              updater.run
            end
          end

          context "when the dependency is not allowed to update" do
            it "does not create the pull request" do
              stub_update_checker(vulnerable?: true)

              job = build_job(
                requested_dependencies: ["dummy-pkg-b"],
                security_advisories: [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "affected-versions" => ["1.1.0"]
                  }
                ],
                allowed_updates: [
                  {
                    "dependency-type" => "development"
                  }
                ],
                security_updates_only: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).not_to receive(:create_pull_request)
              expect(service).to receive(:record_update_job_error).with(
                1,
                {
                  error_type: "all_versions_ignored",
                  error_details: {
                    "dependency-name": "dummy-pkg-b"
                  },
                  dependency: nil
                }
              )
              expect(Dependabot.logger).
                to receive(:info).with(
                  "<job_1> Dependabot cannot update to the required version as all " \
                  "versions were ignored for dummy-pkg-b"
                )

              updater.run
            end
          end

          context "when the dependency is no longer vulnerable" do
            it "does not create pull request" do
              stub_update_checker(vulnerable?: false)

              job = build_job(
                requested_dependencies: ["dummy-pkg-b"],
                security_advisories: [
                  {
                    "dependency-name" => "dummy-pkg-b",
                    "affected-versions" => ["1.0.0"],
                    "patched-versions" => ["1.1.0"]
                  }
                ],
                security_updates_only: true
              )
              service = build_service(job: job)
              updater = build_updater(service: service, job: job)

              expect(service).to_not receive(:create_pull_request)
              expect(service).to receive(:record_update_job_error).with(
                1,
                {
                  error_type: "security_update_not_needed",
                  error_details: {
                    "dependency-name": "dummy-pkg-b"
                  },
                  dependency: nil
                }
              )
              expect(Dependabot.logger).
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
      context "during parsing" do
        context "and it's an unknown error" do
          it "tells Sentry" do
            checker = stub_update_checker
            error = StandardError.new("hell")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(Raven).to receive(:capture_exception)

            updater.run
          end

          it "tells the main backend" do
            checker = stub_update_checker
            error = StandardError.new("hell")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "unknown_error",
                error_details: nil,
                dependency: nil
              )

            updater.run
          end
        end

        context "but it's a Dependabot::DependencyFileNotFound" do
          it "doesn't tell Sentry" do
            checker = stub_update_checker
            error = Dependabot::DependencyFileNotFound.new("path/to/file")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(Raven).to_not receive(:capture_exception)

            updater.run
          end

          it "tells the main backend" do
            checker = stub_update_checker
            error = Dependabot::DependencyFileNotFound.new("path/to/file")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "dependency_file_not_found",
                error_details: { "file-path": "path/to/file" },
                dependency: nil
              )

            updater.run
          end
        end

        context "but it's a Dependabot::BranchNotFound" do
          it "doesn't tell Sentry" do
            checker = stub_update_checker
            error = Dependabot::BranchNotFound.new("my_branch")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(Raven).to_not receive(:capture_exception)

            updater.run
          end

          it "tells the main backend" do
            checker = stub_update_checker
            error = Dependabot::BranchNotFound.new("my_branch")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "branch_not_found",
                error_details: { "branch-name": "my_branch" },
                dependency: nil
              )

            updater.run
          end
        end

        context "but it's a Dependabot::DependencyFileNotParseable" do
          it "doesn't tell Sentry" do
            checker = stub_update_checker
            error = Dependabot::DependencyFileNotParseable.new("path/to/file", "a")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(Raven).to_not receive(:capture_exception)

            updater.run
          end

          it "tells the main backend" do
            checker = stub_update_checker
            error = Dependabot::DependencyFileNotParseable.new("path/to/file", "a")
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "dependency_file_not_parseable",
                error_details: { "file-path": "path/to/file", message: "a" },
                dependency: nil
              )

            updater.run
          end
        end

        context "but it's a Dependabot::PathDependenciesNotReachable" do
          it "doesn't tell Sentry" do
            checker = stub_update_checker
            error = Dependabot::PathDependenciesNotReachable.new(["bad_gem"])
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(Raven).to_not receive(:capture_exception)

            updater.run
          end

          it "tells the main backend" do
            checker = stub_update_checker
            error = Dependabot::PathDependenciesNotReachable.new(["bad_gem"])
            values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
            allow(checker).to receive(:can_update?) { values.shift.call }

            job = build_job
            service = build_service(job: job)
            updater = build_updater(service: service, job: job)

            allow(updater).to receive(:dependency_files).and_raise(error)

            expect(service).
              to receive(:record_update_job_error).
              with(
                1,
                error_type: "path_dependencies_not_reachable",
                error_details: { dependencies: ["bad_gem"] },
                dependency: nil
              )

            updater.run
          end
        end
      end

      context "but it's a Dependabot::DependencyFileNotResolvable" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "dependency_file_not_resolvable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::DependencyFileNotEvaluatable" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "dependency_file_not_evaluatable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::InconsistentRegistryResponse" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "doesn't tell the main backend" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).to_not receive(:record_update_job_error)

          updater.run
        end
      end

      context "but it's a Dependabot::GitDependenciesNotReachable" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "git_dependencies_not_reachable",
              error_details: { "dependency-urls": ["https://example.com"] },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::GitDependencyReferenceNotFound" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "git_dependency_reference_not_found",
              error_details: { dependency: "some_dep" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::GoModulePathMismatch" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "go_module_path_mismatch",
              error_details: {
                "declared-path": "foo",
                "discovered-path": "bar",
                "go-mod": "/go.mod"
              },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::PrivateSourceAuthenticationFailure" do
        it "doesn't tell Sentry" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).to_not receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "private_source_authentication_failure",
              error_details: { source: "some.example.com" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "but it's a Dependabot::SharedHelpers::HelperSubprocessFailed" do
        it "tells the main backend there has been an unknown error" do
          checker = stub_update_checker
          error =
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Potentially sensitive log content goes here",
              error_context: {}
            )
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(service).
            to receive(:record_update_job_error).
            with(
              1,
              error_type: "unknown_error",
              error_details: nil,
              dependency: an_instance_of(Dependabot::Dependency)
            )
          updater.run
        end

        it "notifies Sentry with a breadcrumb to check the logs" do
          checker = stub_update_checker
          error =
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Potentially sensitive log content goes here",
              error_context: {}
            )
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service(job: job)
          updater = build_updater(service: service, job: job)

          expect(Raven).
            to receive(:capture_exception).
            with(instance_of(Dependabot::Updater::SubprocessFailed), anything)

          updater.run
        end
      end

      it "tells Sentry" do
        checker = stub_update_checker
        error = StandardError
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Raven).to receive(:capture_exception).once

        updater.run
      end

      it "tells the main backend" do
        checker = stub_update_checker
        error = StandardError
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(service).
          to receive(:record_update_job_error).
          with(
            1,
            error_type: "unknown_error",
            error_details: nil,
            dependency: an_instance_of(Dependabot::Dependency)
          )

        updater.run
      end

      it "still processes the other jobs" do
        checker = stub_update_checker
        error = StandardError
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end
    end

    describe "experiments" do
      it "passes the experiments to the FileParser as options" do
        stub_update_checker

        job = build_job(
          experiments: {
            "large-hadron-collider" => true
          }
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Dependabot::Bundler::FileParser).to receive(:new).with(
          dependency_files: [
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
          ],
          repo_contents_path: nil,
          source: job.source,
          credentials: [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "github-token"
            },
            { "type" => "random", "secret" => "codes" }
          ],
          reject_external_code: job.reject_external_code?,
          options: { large_hadron_collider: true }
        ).and_call_original

        updater.run
      end

      it "passes the experiments to the FileUpdater as options" do
        stub_update_checker

        job = build_job(
          experiments: {
            "large-hadron-collider" => true
          }
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        expect(Dependabot::Bundler::FileUpdater).to receive(:new).with(
          dependencies: [dependency],
          dependency_files: [
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
          ],
          repo_contents_path: nil,
          credentials: [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "github-token"
            },
            { "type" => "random", "secret" => "codes" }
          ],
          options: { large_hadron_collider: true }
        ).and_call_original

        updater.run
      end

      it "passes the experiments to the UpdateChecker as options" do
        stub_update_checker

        job = build_job(
          experiments: {
            "large-hadron-collider" => true
          }
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

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

      # FIXME: This spec fails (when run outside Dockerfile.updater-core) because mode is being changed to 100666
      context "with a bundler 2 project" do
        it "updates dependencies correctly" do
          stub_update_checker

          job = build_job(
            experiments: {
              "large-hadron-collider" => true
            }
          )
          service = build_service(job: job)
          dependency_files = [
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
          updater = build_updater(service: service, job: job, dependency_files: dependency_files)

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
      job = build_job
      service = build_service(job: job)
      updater = build_updater(service: service, job: job)

      expect(Dependabot.logger).
        not_to receive(:info).
        with(/Ignored versions:/)
      updater.run
    end

    context "with ignore conditions" do
      it "logs ignored versions" do
        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => dependency.name,
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger).
          to have_received(:info).
          with(/Ignored versions:/)
      end

      it "logs ignore conditions" do
        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => dependency.name,
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger).
          to have_received(:info).
          with("<job_1>   >= 1.a, < 2.0.0 - from @dependabot ignore command")
      end

      it "logs ignored update types" do
        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => dependency.name,
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger).
          to have_received(:info).
          with("<job_1>   version-update:semver-patch - from .github/dependabot.yaml")
        expect(Dependabot.logger).
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
        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "dummy-pkg-b",
              "update-types" => ["version-update:semver-patch"],
              "source" => ".github/dependabot.yaml"
            }
          ],
          requested_dependencies: ["dummy-pkg-b"],
          security_updates_only: true
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run
        expect(Dependabot.logger).
          to have_received(:info).
          with(/Ignored versions:/)
      end

      it "logs ignored update types" do
        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "dummy-pkg-b",
              "update-types" => ["version-update:semver-patch"],
              "source" => ".github/dependabot.yaml"
            }
          ],
          requested_dependencies: ["dummy-pkg-b"],
          security_updates_only: true
        )
        service = build_service(job: job)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger).
          to have_received(:info).
          with(
            "<job_1>   version-update:semver-patch - from .github/dependabot.yaml (doesn't apply to security update)"
          )
      end
    end
  end
end
