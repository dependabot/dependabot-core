# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"
require "support/dummy_package_manager/dummy"

require "dependabot/dependency_change"
require "dependabot/environment"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/group_update_all_versions"

require "dependabot/bundler"

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

      # It did not create an individual PR for the dependency that isn't in the existing PR
      # since the rebase could add it.
      expect(dependency_snapshot.ungrouped_dependencies).to be_empty
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
        expect(gemfile_lock.content).to include("rubocop (>= 0.76, < 1.57)")
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
end
