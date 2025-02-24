# typed: false
# frozen_string_literal: true

require "spec_helper"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_snapshot"
require "dependabot/file_fetchers"
require "dependabot/updater"
require "dependabot/service"

require "dependabot/bundler"

### DO NOT ADD NEW TESTS TO THIS FILE
#
# This file tests all of our specific Dependabot::Updater::Operations via the
# top-level Dependabot::Updater interface as it predates us breaking the class
# up.
#
# Any tests should be added to the relevant file in spec/dependabot/operations,
# if it does not exist it should be created, for an example see:
#   updater/spec/dependabot/updater/operations/group_update_all_versions_spec.rb
#
### Migration Path
#
# This file mixes tests that are specific to a single Operation with standard
# behaviours that should be tested against several Operations.
#
# To migrate this file, follow this pattern:
# - Remove all but the target class from Updater::OPERATIONS to 'brown-out'
#   the code paths you aren't focused on
# - Run this spec
# - Copy any _passing_ tests to your new spec/dependabot/operations file
# - Check which of the failing tests should apply to the target Operation
# - Copy them and adjust their setup so they pass
# - Repeat for the next Operation
# - Consider breaking out shared_example groups for any tests which are the same
#   for each Operation
#
# Once this process has been completed, this test should be repurposed to ensure
# that the Updater delegates to the right Operation class and handles halting
# errors in an expected way.
RSpec.describe Dependabot::Updater do
  before do
    allow(Dependabot.logger).to receive(:info)

    stub_request(:get, "https://index.rubygems.org/versions")
      .to_return(status: 200, body: fixture("rubygems-index"))
    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-a")
      .to_return(status: 200, body: fixture("rubygems-info-a"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-a.json")
      .to_return(status: 200, body: fixture("rubygems-versions-a.json"))
    stub_request(:get, "https://index.rubygems.org/info/dummy-pkg-b")
      .to_return(status: 200, body: fixture("rubygems-info-b"))
    stub_request(:get, "https://rubygems.org/api/v1/versions/dummy-pkg-b.json")
      .to_return(status: 200, body: fixture("rubygems-versions-b.json"))
  end

  describe "#run" do
    # FIXME: This spec fails (when run outside Dockerfile.updater-core) because mode is being changed to 100666
    it "updates dependencies correctly" do
      allow(Dependabot.logger).to receive(:error)

      stub_update_checker

      job = build_job
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(service).to receive(:create_pull_request) do |dependency_change, base_commit_sha|
        expect(dependency_change.updated_dependencies.first).to have_attributes(name: "dummy-pkg-b")
        expect(dependency_change.updated_dependency_files_hash).to eql(
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
        expect(base_commit_sha).to eql("sha")
      end

      updater.run
    end

    it "updates only the dependencies that need updating" do
      allow(Dependabot.logger).to receive(:error)

      stub_update_checker

      job = build_job
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(service).to receive(:create_pull_request).once

      updater.run
    end

    it "logs the current and latest versions" do
      allow(Dependabot.logger).to receive(:error)

      stub_update_checker

      job = build_job
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(Dependabot.logger)
        .to receive(:info)
        .with("Checking if dummy-pkg-b 1.1.0 needs updating")
      expect(Dependabot.logger)
        .to receive(:info)
        .with("Latest version is 1.2.0")

      updater.run
    end

    it "does not log empty ignore conditions" do
      allow(Dependabot.logger).to receive(:error)

      job = build_job
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(Dependabot.logger)
        .not_to receive(:info)
        .with(/Ignored versions:/)
      updater.run
    end

    context "when the host is out of disk space" do
      it "records an 'out_of_disk' error" do
        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        allow(job).to receive(:updating_a_pull_request?).and_raise(Errno::ENOSPC)

        updater.run

        expect(service).to have_received(:record_update_job_error)
          .with({ error_type: "out_of_disk", error_details: nil })
      end
    end

    context "when github pr creation is rate limiting" do
      it "records an 'octokit_rate_limited' error" do
        stub_update_checker

        job = build_job
        service = build_service
        error = Octokit::TooManyRequests.new({
          status: 403,
          response_headers: { "X-RateLimit-Reset" => 42 }
        })
        allow(service).to receive(:create_pull_request).and_raise(error)
        updater = build_updater(service: service, job: job)

        updater.run

        expect(service).to have_received(:record_update_job_error)
          .with(
            {
              error_type: "octokit_rate_limited",
              error_details: { "rate-limit-reset": 42 },
              dependency: an_instance_of(Dependabot::Dependency)
            }
          )
      end
    end

    context "when the checker has an requirements update strategy" do
      it "logs the update requirements and strategy" do
        stub_update_checker(requirements_update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions)

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(Dependabot.logger)
          .to receive(:info)
          .with("Requirements to unlock own")
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Requirements update strategy bump_versions")

        updater.run
      end
    end

    context "when lockfile_only is set in the job" do
      it "still tries to unlock requirements of dependencies" do
        checker = stub_update_checker
        allow(checker).to receive(:requirements_unlocked_or_can_be?).and_return(true)

        job = build_job(lockfile_only: true)
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(Dependabot.logger)
          .to receive(:info)
          .with("Requirements to unlock own")

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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(Dependabot.logger)
          .to receive(:info)
          .with("Found no dependencies to update after filtering " \
                "allowed updates in /")
        updater.run
      end
    end

    context "when dealing with a security only updates" do
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
            requested_dependencies: ["dummy-pkg-b"],
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"],
                "patched-versions" => ["1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            {
              error_type: "dependency_file_not_supported",
              error_details: {
                "dependency-name": "dummy-pkg-b"
              }
            }
          )
          expect(Dependabot.logger)
            .to receive(:info).with(
              "Dependabot can't update vulnerable dependencies for " \
              "projects without a lockfile or pinned version requirement as " \
              "the currently installed version of dummy-pkg-b isn't known."
            )

          updater.run
        end
      end

      context "when the update is still vulnerable" do
        it "does not create pull request" do
          checker = stub_update_checker(vulnerable?: true)

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0", "1.2.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(checker).to receive(:lowest_resolvable_security_fix_version)
            .and_return("1.2.0")
          expect(checker).to receive(:lowest_security_fix_version)
            .and_return(Dependabot::Bundler::Version.new("1.3.0"))
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

          expect(service).not_to receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
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
          expect(Dependabot.logger)
            .to receive(:info).with(
              "The latest possible version that can be installed is " \
              "1.2.0 because of the following conflicting dependency:\n" \
              "\n" \
              "  dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.2.0)"
            )

          updater.run
        end
      end

      context "when the update is not possible because the version is required via a transitive dependency" do
        it "does not create pull request" do
          exp_msg = "dummy-pkg-c@1.2.0 requires dummy-pkg-b@1.1.0 via a transitive dependency on dummy-pkg-a@1.2.0"
          conflict = [{ "explanation" => exp_msg,
                        "name" => "dummy-pkg-a",
                        "version" => "1.1.0",
                        "requirement" => "1.2.0" }]
          checker = stub_update_checker(vulnerable?: true, conflicting_dependencies: conflict)

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            security_advisories: [
              {
                "dependency-name" => "dummy-pkg-b",
                "affected-versions" => ["1.1.0"]
              }
            ],
            security_updates_only: true
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(checker).to receive(:lowest_resolvable_security_fix_version)
            .and_return("1.1.0")
          expect(checker).to receive(:lowest_security_fix_version)
            .and_return(Dependabot::Bundler::Version.new("1.2.0"))

          expect(service).not_to receive(:create_pull_request)
          expect(service).to receive(:record_update_job_error).with(
            {
              error_type: "transitive_update_not_possible",
              error_details: {
                "dependency-name": "dummy-pkg-b",
                "latest-resolvable-version": "1.1.0",
                "lowest-non-vulnerable-version": "1.2.0",
                "conflicting-dependencies": [
                  {
                    "explanation" =>
                      "dummy-pkg-c@1.2.0 requires dummy-pkg-b@1.1.0 via a transitive dependency on dummy-pkg-a@1.2.0",
                    "name" => "dummy-pkg-a",
                    "version" => "1.1.0",
                    "requirement" => "1.2.0"
                  }
                ]
              }
            }
          )
          expect(Dependabot.logger)
            .to receive(:info).with(
              "The latest possible version that can be installed is " \
              "1.1.0 because of the following conflicting dependency:\n" \
              "\n" \
              "  dummy-pkg-c@1.2.0 requires dummy-pkg-b@1.1.0 via a transitive dependency on dummy-pkg-a@1.2.0"
            )

          updater.run
        end
      end
    end

    context "when ignore conditions are set" do
      def expect_update_checker_with_ignored_versions(versions, dependency_matcher: anything)
        expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
          dependency: dependency_matcher,
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

      describe "when completely ignoring a dependency" do
        it "no updates are checked, the update is not allowed" do
          stub_update_checker

          job = build_job(
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-a"
              },
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => ">= 0"
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run
          expect(Dependabot::Bundler::UpdateChecker).not_to have_received(:new)
        end
      end

      describe "when ignores match the a dependency being checked" do
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => ">= 1"
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run
          expect_update_checker_with_ignored_versions([">= 1"])
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
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(Dependabot.logger)
            .to receive(:info)
            .with(
              "All updates for dummy-pkg-a were ignored"
            )
          expect(Dependabot.logger)
            .to receive(:info)
            .with(
              "All updates for dummy-pkg-b were ignored"
            )

          updater.run
        end

        it "doesn't report a job error" do
          checker = stub_update_checker
          allow(checker).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)
          allow(checker).to receive(:up_to_date?).and_raise(Dependabot::AllVersionsIgnored)

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect(service).not_to have_received(:record_update_job_error)
        end
      end

      describe "without an ignore condition" do
        it "doesn't enable raised_on_ignore for ignore logging" do
          stub_update_checker

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: having_attributes(name: "dummy-pkg-b"),
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
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => "~> 1.0.0"
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: having_attributes(name: "dummy-pkg-b"),
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
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "update-types" => ["version-update:semver-patch"]
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect(Dependabot::Bundler::UpdateChecker).to have_received(:new).with(
            dependency: having_attributes(name: "dummy-pkg-b"),
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
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-b",
                "version-requirement" => ">= 0"
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions([], dependency_matcher: having_attributes(name: "dummy-pkg-a"))
        end
      end

      describe "when ignores match a wildcard name" do
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
            ignore_conditions: [
              {
                "dependency-name" => "dummy-pkg-*",
                "version-requirement" => ">= 1"
              }
            ]
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions(
            [">= 1"],
            dependency_matcher: having_attributes(name: "dummy-pkg-a")
          )
        end
      end

      describe "when ignores define update-types with feature enabled" do
        it "passes ignored_versions to the update checker" do
          stub_update_checker

          job = build_job(
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
          service = build_service
          updater = build_updater(service: service, job: job)

          updater.run

          expect_update_checker_with_ignored_versions(
            [">= 2.0.0, < 3", "> 1.1.0, < 1.2", ">= 1.2.a, < 2"],
            dependency_matcher: having_attributes(name: "dummy-pkg-b")
          )
        end
      end
    end

    context "when cloning experiment is enabled" do
      it "passes the experiment to the FileUpdater" do
        stub_update_checker

        job = build_job(experiments: { "cloning" => true })
        service = build_service
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
          credentials: anything,
          options: { cloning: true }
        ).and_call_original

        expect(service).to receive(:create_pull_request).once

        updater.run
      end
    end

    context "when an update requires multiple dependencies to be updated" do
      it "updates the dependency" do
        checker = stub_update_checker
        allow(checker)
          .to receive(:can_update?).with(requirements_to_unlock: :own)
          .and_return(false, false)
        allow(checker)
          .to receive(:can_update?).with(requirements_to_unlock: :all)
          .and_return(false, true)

        peer_checker = stub_update_checker(can_update?: false)
        allow(Dependabot::Bundler::UpdateChecker).to receive(:new)
          .and_return(checker, checker, peer_checker)

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end

      context "when the peer dependency could update on its own" do
        it "doesn't update the dependency" do
          checker = stub_update_checker
          allow(checker)
            .to receive(:can_update?).with(requirements_to_unlock: :own)
            .and_return(false, false)
          allow(checker)
            .to receive(:can_update?).with(requirements_to_unlock: :all)
            .and_return(false, true)
          allow(checker).to receive(:updated_dependencies)
            .with(requirements_to_unlock: :all)
            .and_return(
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
          allow(Dependabot::Bundler::UpdateChecker).to receive(:new)
            .and_return(checker, checker, peer_checker)

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
          expect(service).not_to receive(:create_pull_request)

          updater.run
        end
      end

      context "with ignore conditions" do
        it "doesn't set raise_on_ignore for the peer_checker" do
          allow(Dependabot.logger).to receive(:error)
          checker = stub_update_checker
          allow(checker)
            .to receive(:can_update?).with(requirements_to_unlock: :own)
            .and_return(false, false)
          allow(checker)
            .to receive(:can_update?).with(requirements_to_unlock: :all)
            .and_return(false, true)
          allow(checker).to receive(:updated_dependencies)
            .with(requirements_to_unlock: :all)
            .and_return(
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
          service = build_service
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

    context "when a PR already exists for the latest version" do
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(checker).not_to receive(:can_update?)
        expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
        expect(service).not_to receive(:create_pull_request)
        expect(service).not_to receive(:record_update_job_error)
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Pull request already exists for dummy-pkg-b " \
                "with latest version 1.2.0")

        updater.run
      end
    end

    context "when a PR already exists for the resolved version" do
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(checker).to receive(:up_to_date?).and_return(false, false)
        expect(checker).to receive(:can_update?).and_return(true, false)
        expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
        expect(service).not_to receive(:create_pull_request)
        expect(service).not_to receive(:record_update_job_error)
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Pull request already exists for dummy-pkg-b@1.2.0")

        updater.run
      end
    end

    context "when a security update PR exists for the resolved version" do
      it "creates an update job error and short-circuits" do
        checker = stub_update_checker(latest_version: Gem::Version.new("1.3.0"),
                                      vulnerable?: true, conflicting_dependencies: [])

        job = build_job(
          requested_dependencies: ["dummy-pkg-b"],
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(checker).to receive(:up_to_date?).and_return(false)
        expect(checker).to receive(:can_update?).and_return(true)
        expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
        expect(service).not_to receive(:create_pull_request)
        expect(service).to receive(:record_update_job_error)
          .with(
            error_type: "pull_request_exists_for_security_update",
            error_details: {
              "updated-dependencies": [
                "dependency-name": "dummy-pkg-b",
                "dependency-version": "1.2.0"
              ]
            }
          )
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Pull request already exists for dummy-pkg-b@1.2.0")

        updater.run
      end
    end

    context "when a security update PR exists for the latest version" do
      it "doesn't call can_update? (so short-circuits resolution)" do
        checker = stub_update_checker(vulnerable?: true)

        job = build_job(
          requested_dependencies: ["dummy-pkg-b"],
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(checker).not_to receive(:can_update?)
        expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
        expect(service).not_to receive(:create_pull_request)
        expect(service).to receive(:record_update_job_error)
          .with(
            error_type: "pull_request_exists_for_latest_version",
            error_details: {
              "dependency-name": "dummy-pkg-b",
              "dependency-version": "1.2.0"
            },
            dependency: an_instance_of(Dependabot::Dependency)
          )
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Pull request already exists for dummy-pkg-b " \
                "with latest version 1.2.0")

        updater.run
      end
    end

    context "when a PR exists for a different version" do
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end
    end

    context "when a PR already exists for a removed dependency" do
      it "creates an update job error and short-circuits" do
        checker =
          stub_update_checker(
            latest_version: Gem::Version.new("1.3.0"),
            vulnerable?: true,
            conflicting_dependencies: [],
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
          requested_dependencies: ["dummy-pkg-b"],
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
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(checker).to receive(:up_to_date?).and_return(false)
        expect(checker).to receive(:can_update?).and_return(true)
        expect(Dependabot::DependencyChangeBuilder).not_to receive(:create_from)
        expect(service).not_to receive(:create_pull_request)
        expect(service).to receive(:record_update_job_error)
          .with(
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
        expect(Dependabot.logger)
          .to receive(:info)
          .with("Pull request already exists for dummy-pkg-c@1.4.0, dummy-pkg-b@removed")
        updater.run
      end
    end

    context "when a list of dependencies is specified" do
      context "when the job is to update a PR" do
        it "only attempts to update dependencies on the specified list" do
          stub_update_checker

          job = build_job(
            requested_dependencies: ["dummy-pkg-b"],
            updating_a_pull_request: true
          )
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest).to receive(:new).and_call_original
          expect(service).to receive(:create_pull_request).once

          updater.run
        end

        context "when the dependency is a sub-dependency" do
          it "still attempts to update the dependency" do
            stub_update_checker(vulnerable?: true)

            job = build_job(
              requested_dependencies: ["dummy-pkg-a"],
              updating_a_pull_request: true
            )
            service = build_service
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

            expect(Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest).to receive(:new).and_call_original
            expect(service).to receive(:create_pull_request).once

            updater.run
          end
        end

        context "when the dependency isn't vulnerable in a security update" do
          it "closes the pull request" do
            stub_update_checker(vulnerable?: true)

            job = build_job(
              security_updates_only: true,
              requested_dependencies: ["dummy-pkg-b"],
              updating_a_pull_request: true
            )
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once

            updater.run
          end
        end

        context "when the dependency is vulnerable in a security update" do
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:create_pull_request)

            updater.run
          end
        end

        context "when the dependency is vulnerable in a security update but updates aren't allowed" do
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once
            expect(Dependabot.logger)
              .to receive(:info).with(
                "Dependency no longer allowed to update dummy-pkg-b 1.1.0"
              )

            updater.run
          end
        end

        context "when the dependency doesn't appear in the parsed file" do
          it "closes the pull request" do
            job = build_job(
              requested_dependencies: ["removed_dependency"],
              updating_a_pull_request: true
            )
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once

            updater.run
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          it "only attempts to update dependencies on the specified list" do
            stub_update_checker

            job = build_job(
              requested_dependencies: ["Dummy-pkg-b"],
              updating_a_pull_request: true
            )
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest).to receive(:new).and_call_original
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:update_pull_request).once

            updater.run
          end

          context "when dealing with a different version" do
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
              service = build_service
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:close_pull_request).once

            updater.run
          end
        end
      end

      context "when the job is to create a security PR" do
        context "when the dependency is vulnerable and there is no conflicting dependencies" do
          it "creates the pull request" do
            stub_update_checker(vulnerable?: true, conflicting_dependencies: [])

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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:create_pull_request)

            updater.run
          end
        end

        context "when the dependency is vulnerable and there is a conflicting dependencies" do
          it "creates the pull request" do
            conflict = [{ "explanation" => "dummy-pkg-a@10.0.0 requires dummy-pkg-b@1.1.0",
                          "name" => "dummy-pkg-a",
                          "version" => "10.0.0",
                          "requirement" => "1.1.0" }]
            stub_update_checker(vulnerable?: true,
                                conflicting_dependencies: conflict)

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
            service = build_service
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).not_to receive(:create_pull_request)
            expect(service).to receive(:record_update_job_error).with(
              {
                error_type: "all_versions_ignored",
                error_details: {
                  "dependency-name": "dummy-pkg-b"
                }
              }
            )
            expect(Dependabot.logger)
              .to receive(:info).with(
                "Dependabot cannot update to the required version as all " \
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
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).not_to receive(:create_pull_request)
            expect(service).to receive(:record_update_job_error).with(
              {
                error_type: "security_update_not_needed",
                error_details: {
                  "dependency-name": "dummy-pkg-b"
                }
              }
            )
            expect(Dependabot.logger)
              .to receive(:info).with(
                "no security update needed as dummy-pkg-b " \
                "is no longer vulnerable"
              )

            updater.run
          end
        end

        context "when the dependency doesn't appear in the parsed file" do
          it "does not try to close any pull request" do
            stub_update_checker(vulnerable?: true)

            job = build_job(
              requested_dependencies: ["removed_dependency"],
              security_advisories: [
                {
                  "dependency-name" => "removed_dependency",
                  "affected-versions" => ["1.1.0"]
                }
              ],
              security_updates_only: true,
              updating_a_pull_request: false
            )
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).not_to receive(:close_pull_request)

            updater.run
          end
        end

        context "when the dependency name case doesn't match what's parsed" do
          it "still updates dependencies on the specified list" do
            stub_update_checker(vulnerable?: true, conflicting_dependencies: [])

            job = build_job(
              requested_dependencies: ["Dummy-pkg-b"],
              security_advisories: [
                {
                  # TODO: Should advisory name matching be case-insensitive too?
                  "dependency-name" => "Dummy-pkg-b",
                  "affected-versions" => ["1.1.0"]
                }
              ],
              security_updates_only: true,
              updating_a_pull_request: false
            )
            service = build_service
            updater = build_updater(service: service, job: job)

            expect(service).to receive(:create_pull_request).once

            updater.run
          end
        end
      end
    end

    context "when an unknown error is raised while updating dependencies (cloud)" do
      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "reports the error" do
        allow(Dependabot.logger).to receive(:error)
        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:capture_exception).once

        updater.run
      end

      it "tells the main backend" do
        allow(Dependabot.logger).to receive(:error)

        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service)
          .to receive(:record_update_job_error)
          .with(
            error_type: "unknown_error",
            error_details: nil,
            dependency: an_instance_of(Dependabot::Dependency)
          )

        updater.run
      end

      it "continues to process any other dependencies" do
        allow(Dependabot.logger).to receive(:error)

        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end

      context "when Dependabot::DependencyFileNotResolvable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "dependency_file_not_resolvable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::DependencyFileNotEvaluatable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "dependency_file_not_evaluatable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::InconsistentRegistryResponse is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "doesn't tell the main backend" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:record_update_job_error)

          updater.run
        end
      end

      context "when Dependabot::GitDependenciesNotReachable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "git_dependencies_not_reachable",
              error_details: { "dependency-urls": ["https://example.com"] },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::GitDependencyReferenceNotFound is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "git_dependency_reference_not_found",
              error_details: { dependency: "some_dep" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::GoModulePathMismatch is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
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

      context "when Dependabot::PrivateSourceAuthenticationFailure is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "private_source_authentication_failure",
              error_details: { source: "some.example.com" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::SharedHelpers::HelperSubprocessFailed is raised" do
        before do
          allow(Dependabot.logger).to receive(:error)
        end

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
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_unknown_error)
            .with(
              error_type: "unknown_error",
              error_details: {
                Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
                Dependabot::ErrorAttributes::MESSAGE => "Potentially sensitive log content goes here",
                Dependabot::ErrorAttributes::CLASS => "Dependabot::SharedHelpers::HelperSubprocessFailed",
                Dependabot::ErrorAttributes::FINGERPRINT => anything,
                Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
                Dependabot::ErrorAttributes::JOB_ID => "1",
                Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
              }
            )
          updater.run
        end

        it "notifies the service with a breadcrumb to check in the logs" do
          checker = stub_update_checker
          error =
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Potentially sensitive log content goes here",
              error_context: {}
            )
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:capture_exception)
            .with(
              hash_including(
                error: instance_of(Dependabot::Updater::SubprocessFailed),
                job: job
              )
            )

          updater.run
        end
      end
    end

    context "when an unknown error is raised while updating dependencies (ghes)" do
      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, false)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "reports the error" do
        allow(Dependabot.logger).to receive(:error)
        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:capture_exception).once

        updater.run
      end

      it "tells the main backend" do
        allow(Dependabot.logger).to receive(:error)

        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service)
          .to receive(:record_update_job_error)
          .with(
            error_type: "unknown_error",
            error_details: nil,
            dependency: an_instance_of(Dependabot::Dependency)
          )

        updater.run
      end

      it "continues to process any other dependencies" do
        allow(Dependabot.logger).to receive(:error)

        checker = stub_update_checker
        error = StandardError.new("hell")
        values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
        allow(checker).to receive(:can_update?) { values.shift.call }

        job = build_job
        service = build_service
        updater = build_updater(service: service, job: job)

        expect(service).to receive(:create_pull_request).once

        updater.run
      end

      context "when Dependabot::DependencyFileNotResolvable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotResolvable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "dependency_file_not_resolvable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::DependencyFileNotEvaluatable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::DependencyFileNotEvaluatable.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "dependency_file_not_evaluatable",
              error_details: { message: "message" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::InconsistentRegistryResponse is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "doesn't tell the main backend" do
          checker = stub_update_checker
          error = Dependabot::InconsistentRegistryResponse.new("message")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:record_update_job_error)

          updater.run
        end
      end

      context "when Dependabot::PrivateSourceAuthenticationFailure is raised with Unauthenticated message" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("npm.fury.io")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("npm.fury.io")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "private_source_authentication_failure",
              error_details: { source: "npm.fury.io" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::GitDependenciesNotReachable is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependenciesNotReachable.new("https://example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "git_dependencies_not_reachable",
              error_details: { "dependency-urls": ["https://example.com"] },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when URI::InvalidURIError is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = URI::InvalidURIError.new("https://registry.yarnpkg.com}/")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = URI::InvalidURIError.new("https://registry.yarnpkg.com}/")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "dependency_file_not_resolvable",
              error_details: { message: "https://registry.yarnpkg.com}/" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::GitDependencyReferenceNotFound is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GitDependencyReferenceNotFound.new("some_dep")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "git_dependency_reference_not_found",
              error_details: { dependency: "some_dep" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::GoModulePathMismatch is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::GoModulePathMismatch.new("/go.mod", "foo", "bar")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
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

      context "when Dependabot::PrivateSourceAuthenticationFailure is raised" do
        it "doesn't report the error to the service" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service).not_to receive(:capture_exception)

          updater.run
        end

        it "tells the main backend" do
          checker = stub_update_checker
          error = Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com")
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "private_source_authentication_failure",
              error_details: { source: "some.example.com" },
              dependency: an_instance_of(Dependabot::Dependency)
            )

          updater.run
        end
      end

      context "when Dependabot::SharedHelpers::HelperSubprocessFailed is raised" do
        before do
          allow(Dependabot.logger).to receive(:error)
        end

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
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:record_update_job_error)
            .with(
              error_type: "unknown_error",
              error_details: nil,
              dependency: an_instance_of(Dependabot::Dependency)
            )
          updater.run
        end

        it "notifies the service with a breadcrumb to check in the logs" do
          checker = stub_update_checker
          error =
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Potentially sensitive log content goes here",
              error_context: {}
            )
          values = [-> { raise error }, -> { true }, -> { true }, -> { true }]
          allow(checker).to receive(:can_update?) { values.shift.call }

          job = build_job
          service = build_service
          updater = build_updater(service: service, job: job)

          expect(service)
            .to receive(:capture_exception)
            .with(
              hash_including(
                error: instance_of(Dependabot::Updater::SubprocessFailed),
                job: job
              )
            )

          updater.run
        end
      end
    end

    describe "experiments" do
      it "passes the experiments to the FileUpdater as options" do
        stub_update_checker

        job = build_job(
          experiments: {
            "large-hadron-collider" => true
          }
        )
        service = build_service
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
          credentials: anything,
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
        service = build_service
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
          service = build_service
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

          expect(service).to receive(:create_pull_request) do |dependency_change, base_commit_sha|
            expect(dependency_change.updated_dependencies.first).to have_attributes(name: "dummy-pkg-b")
            expect(dependency_change.updated_dependency_files_hash).to eql(
              [
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
            )
            expect(base_commit_sha).to eql("sha")
          end

          updater.run
        end
      end
    end

    context "with ignore conditions" do
      it "logs ignored versions" do
        allow(Dependabot.logger).to receive(:error)

        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger)
          .to have_received(:info)
          .with(/Ignored versions:/)
      end

      it "logs ignore conditions" do
        allow(Dependabot.logger).to receive(:error)

        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger)
          .to have_received(:info)
          .with("  >= 1.a, < 2.0.0 - from @dependabot ignore command")
      end

      it "logs ignored update types" do
        allow(Dependabot.logger).to receive(:error)

        job = build_job(
          ignore_conditions: [
            {
              "dependency-name" => "*-pkg-b",
              "update-types" => ["version-update:semver-patch", "version-update:semver-minor"],
              "source" => ".github/dependabot.yaml"
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "version-requirement" => ">= 1.a, < 2.0.0",
              "source" => "@dependabot ignore command"
            }
          ]
        )
        service = build_service
        updater = build_updater(service: service, job: job)

        updater.run

        expect(Dependabot.logger)
          .to have_received(:info)
          .with("  version-update:semver-patch - from .github/dependabot.yaml")
        expect(Dependabot.logger)
          .to have_received(:info)
          .with("  version-update:semver-minor - from .github/dependabot.yaml")
      end
    end

    context "with ignored versions that don't apply during a security update" do
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
        service = build_service
        updater = build_updater(service: service, job: job)

        checker = stub_update_checker
        allow(checker).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)

        updater.run
        expect(Dependabot.logger)
          .to have_received(:info)
          .with(/Ignored versions:/)
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
        service = build_service
        updater = build_updater(service: service, job: job)

        checker = stub_update_checker
        allow(checker).to receive(:latest_version).and_raise(Dependabot::AllVersionsIgnored)

        updater.run

        expect(Dependabot.logger)
          .to have_received(:info)
          .with(
            "  version-update:semver-patch - from .github/dependabot.yaml (doesn't apply to security update)"
          )
      end
    end
  end

  # TODO: Expand this unit test to exercise creation of a PR with multiple changes
  #
  # This is currently just a very simple litmus test that the adapter for grouped updates
  # is not broken, we rely on a smoke test to do blind testing of the "real" grouping
  # function for now.
  describe "#run with the grouped experiment enabled" do
    after do
      Dependabot::Experiments.reset!
    end

    it "updates multiple dependencies in a single PR correctly" do
      job = build_job(experiments: { "grouped-updates-prototype" => true })
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(service).to receive(:create_pull_request) do |dependency_change, base_commit_sha|
        expect(dependency_change.updated_dependencies.first).to have_attributes(name: "dummy-pkg-b")
        expect(dependency_change.updated_dependency_files_hash).to eql(
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
        expect(base_commit_sha).to eql("sha")
      end

      updater.run
    end

    it "does not include ignored dependencies in the group PR" do
      job = build_job(
        ignore_conditions: [
          {
            "dependency-name" => "dummy-pkg-b",
            "version-requirement" => ">= 0"
          }
        ],
        experiments: { "grouped-updates-prototype" => true }
      )
      service = build_service
      updater = build_updater(service: service, job: job)

      expect(service).not_to receive(:create_pull_request)
      updater.run
    end
  end

  def build_updater(service: build_service, job: build_job, dependency_files: default_dependency_files,
                    dependency_snapshot: nil)
    Dependabot::Updater.new(
      service: service,
      job: job,
      dependency_snapshot: dependency_snapshot || build_dependency_snapshot(
        job: job, dependency_files: dependency_files
      )
    )
  end

  def build_dependency_snapshot(job:, dependency_files: default_dependency_files)
    Dependabot::DependencySnapshot.new(
      job: job,
      dependency_files: dependency_files,
      base_commit_sha: "sha"
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

  def build_service
    # Stub out a client so we don't hit the internet
    api_client = instance_double(
      Dependabot::ApiClient,
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      mark_job_as_processed: nil,
      record_update_job_error: nil,
      record_update_job_unknown_error: nil,
      increment_metric: nil,
      record_ecosystem_meta: nil
    )
    allow(api_client).to receive(:is_a?).with(Dependabot::ApiClient).and_return(true)

    service = Dependabot::Service.new(
      client: api_client
    )
    allow(service).to receive(:record_update_job_error)
    allow(service).to receive(:record_update_job_unknown_error)
    allow(service).to receive(:is_a?).with(Dependabot::Service).and_return(true)

    service
  end

  # rubocop:disable Metrics/MethodLength
  def build_job(requested_dependencies: nil, allowed_updates: default_allowed_updates, existing_pull_requests: [],
                existing_group_pull_requests: [], ignore_conditions: [], security_advisories: [], experiments: {},
                updating_a_pull_request: false, security_updates_only: false, dependency_groups: [],
                lockfile_only: false, repo_contents_path: nil)
    Dependabot::Job.new(
      id: "1",
      token: "token",
      dependencies: requested_dependencies,
      allowed_updates: allowed_updates,
      existing_pull_requests: existing_pull_requests,
      existing_group_pull_requests: existing_group_pull_requests,
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
      lockfile_only: lockfile_only,
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
      security_updates_only: security_updates_only,
      repo_contents_path: repo_contents_path,
      dependency_groups: dependency_groups
    )
  end
  # rubocop:enable Metrics/MethodLength

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
end
