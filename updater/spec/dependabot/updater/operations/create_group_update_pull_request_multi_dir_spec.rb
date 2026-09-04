# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/create_group_update_pull_request"
require "dependabot/updater/group_dependency_selector"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

# End-to-end test for multi-directory grouped PR creation.
#
# A terraform monorepo has 3 directories, each with the same 3 providers. On a grouped
# creation job, compile_all_dependency_changes_for is called per directory and the results
# are combined via filter_map. When every directory is filtered out (nothing can update),
# the array is empty and the old T.must(dependency_changes.first) raised
# `TypeError: Passed nil into T.must` (Sentry DELTAFORCE-1K1Y). This exercises the public
# #perform to prove the guard returns nil instead of crashing.
RSpec.describe Dependabot::Updater::Operations::CreateGroupUpdatePullRequest do
  describe "#perform with multi-directory groups" do
    subject(:create_operation) do
      described_class.new(
        service: mock_service,
        job: job,
        dependency_snapshot: dependency_snapshot,
        error_handler: mock_error_handler,
        group: dependency_group
      )
    end

    let(:directories) { ["/dir1", "/dir2", "/dir3"] }
    let(:dep_names) { %w(hashicorp/aws hashicorp/google hashicorp/kubernetes) }

    let(:mock_service) do
      instance_double(
        Dependabot::Service,
        increment_metric: nil,
        record_update_job_error: nil,
        record_update_job_warning: nil,
        record_ecosystem_meta: nil,
        record_cooldown_meta: nil
      )
    end

    let(:mock_error_handler) do
      instance_double(Dependabot::Updater::ErrorHandler, handle_dependency_error: nil)
    end

    let(:dependency_files) do
      directories.map do |dir|
        Dependabot::DependencyFile.new(
          name: "main.tf",
          content: "# terraform config",
          directory: dir
        )
      end
    end

    let(:job) do
      Dependabot::Job.new_update_job(
        job_id: "1234",
        job_definition: {
          "job" => {
            "package-manager" => "terraform",
            "source" => {
              "provider" => "github",
              "repo" => "test/terraform-monorepo",
              "directories" => directories,
              "branch" => nil,
              "api-endpoint" => "https://api.github.com/",
              "hostname" => "github.com"
            },
            "dependencies" => dep_names,
            "existing-pull-requests" => [],
            "existing-group-pull-requests" => [],
            "updating-a-pull-request" => false,
            "lockfile-only" => false,
            "update-subdependencies" => false,
            "ignore-conditions" => [],
            "requirements-update-strategy" => nil,
            "allowed-updates" => [{ "dependency-type" => "direct", "update-type" => "all" }],
            "credentials-metadata" => [{ "type" => "git_source", "host" => "github.com" }],
            "security-advisories" => [],
            "vendor-dependencies" => false,
            "experiments" => { "grouped-updates-prototype" => true },
            "reject-external-code" => false,
            "commit-message-options" => {},
            "security-updates-only" => false,
            "dependency-groups" => [{
              "name" => "all-terraform",
              "rules" => { "patterns" => ["*"] }
            }]
          }
        }
      )
    end

    let(:dependency_snapshot) do
      Dependabot::DependencySnapshot.create_from_job_definition(
        job: job,
        fetched_files: Dependabot::FetchedFiles.new(
          base_commit_sha: "mock-sha",
          dependency_files: dependency_files
        )
      )
    end

    let(:dependency_group) do
      dependency_snapshot.groups.find { |g| g.name == "all-terraform" }
    end

    let(:ecosystem) do
      Dependabot::Ecosystem.new(
        name: "terraform",
        package_manager: DummyPkgHelpers::StubPackageManager.new(
          name: "terraform", version: "1.5.0", supported_versions: %w(1.5 1.6)
        )
      )
    end

    before do
      # Register fake implementations BEFORE dependency_snapshot is created.
      # DependencySnapshot#initialize calls parse_files! which needs these.
      Dependabot::Dependency.register_production_check("terraform", ->(_groups) { true })

      Dependabot::FileParsers.register(
        "terraform",
        Class.new(Dependabot::FileParsers::Base) do
          define_method(:parse) do
            dir = source&.directory || "/"
            %w(hashicorp/aws hashicorp/google hashicorp/kubernetes).map do |name|
              Dependabot::Dependency.new(
                name: name,
                version: "4.0.0",
                requirements: [{
                  file: "main.tf", requirement: "~> 4.0", groups: [],
                  source: { type: "provider", registry_hostname: "registry.terraform.io",
                            module_identifier: name }
                }],
                package_manager: "terraform",
                directory: dir
              )
            end
          end
          define_method(:ecosystem) { nil }
          define_method(:check_required_files) { nil }
        end
      )

      Dependabot::UpdateCheckers.register(
        "terraform",
        Class.new(Dependabot::UpdateCheckers::Base) do
          define_method(:latest_version) { Gem::Version.new("5.0.0") }
          define_method(:latest_resolvable_version) { Gem::Version.new("5.0.0") }
          define_method(:latest_resolvable_version_with_no_unlock) { Gem::Version.new("5.0.0") }
          define_method(:lowest_security_fix_version) { nil }
          define_method(:lowest_resolvable_security_fix_version) { nil }
          define_method(:updated_requirements) do
            dependency.requirements.map { |r| r.merge(requirement: "~> 5.0") }
          end
          define_method(:up_to_date?) { false }
          define_method(:requirements_unlocked_or_can_be?) { true }
          define_method(:can_update?) { |**_kwargs| true }
          define_method(:updated_dependencies) do |**_kwargs|
            [Dependabot::Dependency.new(
              name: dependency.name,
              version: "5.0.0",
              requirements: dependency.requirements.map { |r| r.merge(requirement: "~> 5.0") },
              previous_version: "4.0.0",
              previous_requirements: dependency.requirements,
              package_manager: "terraform",
              directory: dependency.directory
            )]
          end
        end
      )

      Dependabot::FileUpdaters.register(
        "terraform",
        Class.new(Dependabot::FileUpdaters::Base) do
          define_method(:updated_dependency_files) do
            dependency_files.map do |f|
              Dependabot::DependencyFile.new(name: f.name, content: "# updated", directory: f.directory)
            end
          end
          define_method(:check_required_files) { nil }
        end
      )

      Dependabot::Utils.register_version_class("terraform", Dependabot::Version)
      Dependabot::Utils.register_requirement_class("terraform", Dependabot::Requirement)

      Dependabot::Experiments.reset!

      allow(dependency_snapshot).to receive(:ecosystem).and_return(ecosystem)
      allow(job).to receive(:package_manager).and_return("terraform")
    end

    after do
      Dependabot::Experiments.reset!
    end

    it "creates a pull request with exactly 3 updated dependencies per directory" do
      dependency_change = nil
      allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

      create_operation.perform

      expect(dependency_change).not_to be_nil
      expect(dependency_change.updated_dependencies.length).to eq(9)
    end

    context "when no directory produces a change" do
      before do
        # Re-register an update checker whose updates are missing a previous version and
        # leave requirements unchanged. compile_all_dependency_changes_for then fails its
        # all_have_previous_version? check and returns nil for every directory, so the
        # multi-directory filter_map collapses to an empty array (the crash condition).
        Dependabot::UpdateCheckers.register(
          "terraform",
          Class.new(Dependabot::UpdateCheckers::Base) do
            define_method(:latest_version) { Gem::Version.new("5.0.0") }
            define_method(:latest_resolvable_version) { Gem::Version.new("5.0.0") }
            define_method(:latest_resolvable_version_with_no_unlock) { Gem::Version.new("5.0.0") }
            define_method(:lowest_security_fix_version) { nil }
            define_method(:lowest_resolvable_security_fix_version) { nil }
            define_method(:updated_requirements) { dependency.requirements }
            define_method(:up_to_date?) { false }
            define_method(:requirements_unlocked_or_can_be?) { true }
            define_method(:can_update?) { |**_kwargs| true }
            define_method(:updated_dependencies) do |**_kwargs|
              [Dependabot::Dependency.new(
                name: dependency.name,
                version: "5.0.0",
                requirements: dependency.requirements,
                previous_version: nil,
                previous_requirements: dependency.requirements,
                package_manager: "terraform",
                directory: dependency.directory
              )]
            end
          end
        )
      end

      it "returns nil so the caller marks the group handled, without opening a PR" do
        expect(mock_service).not_to receive(:create_pull_request)

        result = "unset"
        expect { result = create_operation.perform }.not_to raise_error

        # nil (not an empty DependencyChange) is what GroupUpdateAllVersions keys on to
        # mark the group handled, so assert it directly rather than just "no PR".
        expect(result).to be_nil
      end
    end
  end
end
