# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_group_update_pull_request"
require "dependabot/updater/group_dependency_selector"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

# End-to-end test for the multi-directory duplicate dependency bug.
#
# Scenario: A terraform monorepo has 3 directories, each with the same 3 providers.
# On a group refresh job, compile_all_dependency_changes_for is called per directory.
# The bug caused each directory to report N*3 updated deps (where N = number of dirs)
# instead of just 3, because group.dependencies accumulated entries from all directories
# and skip_dependency? didn't filter by directory.
RSpec.describe Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest do
  describe "#perform with multi-directory groups" do
    subject(:refresh_operation) do
      described_class.new(
        service: mock_service,
        job: job,
        dependency_snapshot: dependency_snapshot,
        error_handler: mock_error_handler
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

    # Build dependency files for each directory
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
            "existing-group-pull-requests" => [{
              "dependency-group-name" => "all-terraform",
              "dependencies" => dep_names.flat_map do |name|
                directories.map do |dir|
                  { "dependency-name" => name, "dependency-version" => "4.0.0", "directory" => dir }
                end
              end
            }],
            "updating-a-pull-request" => true,
            "lockfile-only" => false,
            "update-subdependencies" => false,
            "ignore-conditions" => [],
            "requirements-update-strategy" => nil,
            "allowed-updates" => [{ "dependency-type" => "direct", "update-type" => "all" }],
            "credentials-metadata" => [{ "type" => "git_source", "host" => "github.com" }],
            "security-advisories" => [],
            "max-updater-run-time" => 2700,
            "vendor-dependencies" => false,
            "experiments" => { "grouped-updates-prototype" => true },
            "reject-external-code" => false,
            "commit-message-options" => {},
            "security-updates-only" => false,
            "dependency-groups" => [{
              "name" => "all-terraform",
              "rules" => { "patterns" => ["*"] }
            }],
            "dependency-group-to-refresh" => "all-terraform"
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
      Dependabot::Experiments.register(:allow_refresh_group_with_all_dependencies, true)

      allow(dependency_snapshot).to receive(:ecosystem).and_return(ecosystem)
      allow(job).to receive(:package_manager).and_return("terraform")
    end

    after do
      Dependabot::Experiments.reset!
    end

    it "produces exactly 3 updated dependencies per directory, not 3*N" do
      dependency_change = nil
      allow(mock_service).to receive(:update_pull_request) { |change| dependency_change = change }
      allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

      refresh_operation.perform

      expect(dependency_change).not_to be_nil

      # With 3 directories × 3 deps, correct behavior = 9 total (3 per dir).
      # Bug would produce 27 (9 per dir × 3 dirs due to cross-dir contamination).
      updated_count = dependency_change.updated_dependencies.length
      expect(updated_count).to eq(9), "Expected 9 updated deps but got #{updated_count}"
    end

    it "has no duplicate dependency name+directory combinations" do
      dependency_change = nil
      allow(mock_service).to receive(:update_pull_request) { |change| dependency_change = change }
      allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

      refresh_operation.perform

      expect(dependency_change).not_to be_nil

      name_dir_pairs = dependency_change.updated_dependencies.map { |d| [d.name, d.directory] }
      duplicates = name_dir_pairs.tally.select { |_pair, count| count > 1 }
      expect(duplicates).to be_empty, "Found duplicate (name, directory) pairs: #{duplicates.keys.inspect}"
    end
  end
end
