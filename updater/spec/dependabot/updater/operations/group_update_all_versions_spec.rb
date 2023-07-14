# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/environment"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/group_update_all_versions"

RSpec.describe Dependabot::Updater::Operations::GroupUpdateAllVersions do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:group_update_all) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(Dependabot::Service, increment_metric: nil)
  end

  let(:job) do
    Dependabot::Job.new_update_job(
      job_id: "1558782000",
      job_definition: job_definition_with_fetched_files
    )
  end

  let(:dependency_snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      job_definition: job_definition_with_fetched_files
    )
  end

  let(:job_definition_with_fetched_files) do
    job_definition.merge({
      "base_commit_sha" => "mock-sha",
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    })
  end

  let(:mock_error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler)
  end

  after do
    Dependabot::Experiments.reset!
  end

  context "when only some dependencies match the defined group" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_with_ungrouped")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "performs a grouped and ungrouped dependency update when both are present" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("group-b")

        # We updated the right depednencies
        expect(dependency_change.updated_dependencies.length).to eql(1)
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(dummy-pkg-b))

        # We updated the right files correctly.
        expect(dependency_change.updated_dependency_files_hash.length).to eql(2)
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      expect(Dependabot::Updater::Operations::UpdateAllVersions).to receive(:new) do |args|
        expect(args[:dependency_snapshot].ungrouped_dependencies.length).to eql(1)
        expect(args[:dependency_snapshot].ungrouped_dependencies.first.name).to eql("dummy-pkg-a")
      end.and_return(instance_double(Dependabot::Updater::Operations::UpdateAllVersions, perform: nil))

      group_update_all.perform
    end
  end

  context "when the snapshot has no groups configured" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/update_all_simple")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "logs a warning, reports an error but defers everything to individual updates" do
      # Our mocks will fail due to unexpected messages if any errors or PRs are dispatched
      expect(Dependabot.logger).to receive(:warn).with("No dependency groups defined!")

      expect(mock_service).to receive(:capture_exception).with(
        error: an_instance_of(Dependabot::DependabotError),
        job: job
      )

      expect(Dependabot::Updater::Operations::UpdateAllVersions).to receive(:new) do |args|
        expect(args[:dependency_snapshot].ungrouped_dependencies.length).to eql(2)
        expect(args[:dependency_snapshot].ungrouped_dependencies.first.name).to eql("dummy-pkg-a")
        expect(args[:dependency_snapshot].ungrouped_dependencies.last.name).to eql("dummy-pkg-b")
      end.and_return(instance_double(Dependabot::Updater::Operations::UpdateAllVersions, perform: nil))

      group_update_all.perform
    end
  end

  context "when the snapshot has a group that does not match any dependencies" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_empty_group")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "warns the group is empty" do
      allow(Dependabot.logger).to receive(:warn) # permit any other warning calls that happen
      expect(Dependabot.logger).to receive(:warn).with(
        "Skipping update group for 'everything-everywhere-all-at-once' as it does not match any allowed dependencies."
      )

      # Expect us to handle the dependencies individually instead
      expect(Dependabot::Updater::Operations::UpdateAllVersions).to receive(:new).and_return(
        instance_double(Dependabot::Updater::Operations::UpdateAllVersions, perform: nil)
      )

      group_update_all.perform
    end

    context "when debug is enabled" do
      before do
        allow(Dependabot.logger).to receive(:debug)
        allow(Dependabot.logger).to receive(:debug?).and_return(true)
      end

      it "renders the group configuration for us" do
        expect(Dependabot.logger).to receive(:debug).with(
          <<~DEBUG
            The configuration for this group is:

            groups:
              everything-everywhere-all-at-once:
                patterns:
                - "*bagel"
          DEBUG
        )

        # Expect us to handle the dependencies individually instead
        expect(Dependabot::Updater::Operations::UpdateAllVersions).to receive(:new).and_return(
          instance_double(Dependabot::Updater::Operations::UpdateAllVersions, perform: nil)
        )

        group_update_all.perform
      end
    end
  end

  context "when there are two overlapping groups" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_overlapping_groups")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "creates a pull request for each containing the same dependencies" do
      allow(Dependabot.logger).to receive(:info)
      expect(Dependabot.logger).to receive(:info).with(
        "Found 2 group(s)."
      )

      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("my-group")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("my-overlapping-group")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when the snapshot is only grouping minor- and patch-level changes", :vcr do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_semvar_grouping")
    end

    let(:dependency_files) do
      original_bundler_files(fixture: "bundler_grouped_by_types")
    end

    it "creates a group PR for minor- and patch-level changes and individual PRs for major-level changes" do
      # We should create a group PR with the latest minor versions for rack and rubocop
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("small-bumps")

        # We updated the right dependencies
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rack rubocop))

        # We've updated the gemfiles properly
        gemfile = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile"
        end
        expect(gemfile.content).to eql(fixture("bundler_grouped_by_types/updated_minor_and_patch/Gemfile"))

        gemfile_lock = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile.lock"
        end
        expect(gemfile_lock.content).to eql(fixture("bundler_grouped_by_types/updated_minor_and_patch/Gemfile.lock"))
      end

      # # We should also create isolated PRs for their major versions
      # expect(mock_service).to receive(:create_pull_request) do |dependency_change|
      #   expect(dependency_change.dependency_group).to be_nil

      #   # We updated the right dependencies
      #   expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rack))
      # end

      # # We should also create isolated PRs for their major versions
      # expect(mock_service).to receive(:create_pull_request) do |dependency_change|
      #   expect(dependency_change.dependency_group).to be_nil

      #   # We updated the right dependencies
      #   expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rubocop))
      # end

      group_update_all.perform
    end
  end

  context "when a pull request already exists for a group" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_with_existing_pr")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "does not create a new pull request for a group if one already exists" do
      allow(Dependabot.logger).to receive(:info)
      expect(Dependabot.logger).to receive(:info).with(
        "Detected existing pull request for 'group-b'."
      )

      group_update_all.perform
    end
  end

  context "when nothing in the group needs to be updated" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all")
    end

    let(:dependency_files) do
      # Let's use the already up-to-date files
      updated_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "raises no errors and creates no pull requests" do
      # Our mocks will fail due to unexpected messages if any errors or PRs are dispatched
      group_update_all.perform
    end
  end

  context "when the snapshot is updating a gemspec", :vcr do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all")
    end

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_gemspec/original/Gemfile"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_gemspec/original/Gemfile.lock"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "library.gemspec",
          content: fixture("bundler_gemspec/original/library.gemspec"),
          directory: "/"
        )
      ]
    end

    it "creates a DependencyChange for just the modified files without reporting errors" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")

        # We updated the right depednencies
        expect(dependency_change.updated_dependencies.length).to eql(2)
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rubocop rack))

        # We updated the right files correctly.
        expect(dependency_change.updated_dependency_files_hash.length).to eql(2)

        gemspec = dependency_change.updated_dependency_files.find { |file| file.path == "/library.gemspec" }
        expect(gemspec.content).to eql(fixture("bundler_gemspec/updated/library.gemspec"))

        gemfile_lock = dependency_change.updated_dependency_files.find { |file| file.path == "/Gemfile.lock" }
        # Since we are actually running bundler for this test, let's just check the Gemfile.lock has been updated
        # with the same ranges as the library.gemspec rather than expecting the entire lockfile to match.
        expect(gemfile_lock.content).to include("rack (>= 2.1.4, < 3.1.0)")
        expect(gemfile_lock.content).to include("rubocop (>= 0.76, < 1.51)")
      end

      group_update_all.perform
    end
  end

  context "when the snapshot is updating several peer manifests", :vcr do
    let(:job_definition) do
      job_definition_fixture("docker/version_updates/group_update_peer_manifests")
    end

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Dockerfile.bundler",
          content: fixture("docker/original/Dockerfile.bundler"),
          directory: "/docker"
        ),
        Dependabot::DependencyFile.new(
          name: "Dockerfile.cargo",
          content: fixture("docker/original/Dockerfile.cargo"),
          directory: "/docker"
        )
      ]
    end

    it "creates a DependencyChange for both of the manifests without reporting errors" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("dependabot-core-images")

        # We updated the right depednencies
        expect(dependency_change.updated_dependencies.length).to eql(2)
        expect(dependency_change.updated_dependencies.map(&:name)).
          to eql(%w(dependabot/dependabot-updater-bundler dependabot/dependabot-updater-cargo))

        # We updated the right files.
        expect(dependency_change.updated_dependency_files_hash.length).to eql(2)
        expect(dependency_change.updated_dependency_files.map(&:name)).
          to eql(%w(Dockerfile.bundler Dockerfile.cargo))
      end

      group_update_all.perform
    end
  end

  context "when the snapshot is updating vendored dependencies", :vcr do
    let(:job) do
      Dependabot::Job.new_update_job(
        job_id: "1558782000",
        job_definition: job_definition_with_fetched_files,
        repo_contents_path: create_temporary_content_directory(fixture: "bundler_vendored", directory: "bundler/")
      )
    end

    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_with_vendoring")
    end

    let(:dependency_files) do
      original_bundler_files(fixture: "bundler_vendored", directory: "bundler/")
    end

    before do
      stub_rubygems_calls
    end

    it "creates a pull request that includes changes to the vendored files" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")

        # We updated the right dependencies
        expect(dependency_change.updated_dependencies.length).to eql(2)
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(dummy-pkg-b dummy-git-dependency))

        # We updated the right files correctly.
        expect(dependency_change.updated_dependency_files_hash.length).to eql(8)

        # We've updated the gemfiles properly
        gemfile = dependency_change.updated_dependency_files.find do |file|
          file.path == "/bundler/Gemfile"
        end
        expect(gemfile.content).to eql(fixture("bundler_vendored/updated/Gemfile"))

        gemfile_lock = dependency_change.updated_dependency_files.find do |file|
          file.path == "/bundler/Gemfile.lock"
        end
        expect(gemfile_lock.content).to eql(fixture("bundler_vendored/updated/Gemfile.lock"))

        # We've deleted the old version of dummy-pkg-b
        old_dummy_pkg_b = dependency_change.updated_dependency_files.find do |file|
          file.path == "/bundler/vendor/cache/dummy-pkg-b-1.1.0.gem"
        end
        expect(old_dummy_pkg_b.operation).to eql("delete")

        # We've created the new version of dummy-pkg-b
        new_dummy_pkg_b = dependency_change.updated_dependency_files.find do |file|
          file.path == "/bundler/vendor/cache/dummy-pkg-b-1.2.0.gem"
        end
        expect(new_dummy_pkg_b.operation).to eql("create")

        # We've deleted the old version of the vendored git dependency
        old_git_dependency_files = dependency_change.updated_dependency_files.select do |file|
          file.path.start_with?("/bundler/vendor/cache/ruby-dummy-git-dependency-20151f9b67c8")
        end
        expect(old_git_dependency_files.map(&:operation)).to eql(%w(delete delete))

        # We've created the new version of the vendored git dependency
        new_git_dependency_files = dependency_change.updated_dependency_files.select do |file|
          file.path.start_with?("/bundler/vendor/cache/ruby-dummy-git-dependency-c0e25c2eb332")
        end
        expect(new_git_dependency_files.map(&:operation)).to eql(%w(create create))
      end

      group_update_all.perform
    end
  end

  context "when the snapshop is updating dependencies split by dependency-type", :vcr do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all_by_dependency_type")
    end

    let(:dependency_files) do
      original_bundler_files(fixture: "bundler_grouped_by_types")
    end

    it "creates separate pull requests for development and production dependencies" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("dev-dependencies")

        # We updated the right dependencies
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rubocop))

        # We've updated the gemfiles properly
        gemfile = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile"
        end
        expect(gemfile.content).to eql(fixture("bundler_grouped_by_types/updated_development_deps/Gemfile"))

        gemfile_lock = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile.lock"
        end
        expect(gemfile_lock.content).to eql(fixture("bundler_grouped_by_types/updated_development_deps/Gemfile.lock"))
      end

      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("production-dependencies")

        # We updated the right dependencies
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rack))

        # We've updated the gemfiles properly
        gemfile = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile"
        end
        expect(gemfile.content).to eql(fixture("bundler_grouped_by_types/updated_production_deps/Gemfile"))

        gemfile_lock = dependency_change.updated_dependency_files.find do |file|
          file.path == "/Gemfile.lock"
        end
        expect(gemfile_lock.content).to eql(fixture("bundler_grouped_by_types/updated_production_deps/Gemfile.lock"))
      end

      group_update_all.perform
    end
  end
end
