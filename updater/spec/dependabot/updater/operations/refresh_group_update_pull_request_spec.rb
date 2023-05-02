# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_group_update_pull_request"

RSpec.describe Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest do
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
    Dependabot::DependencyGroupEngine.reset!
  end

  context "when the same dependencies need to be updated to the same target versions" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "updates the existing pull request without errors" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:update_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when the dependencies have been since been updated by someone else and there's nothing to do" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh")
    end

    let(:dependency_files) do
      updated_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "closes the pull request" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:close_pull_request).with(["dummy-pkg-b"], :up_to_date)

      group_update_all.perform
    end
  end

  context "when the dependencies that need to be updated have changed" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_dependencies_changed")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "closes the existing pull request and creates a new one" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:close_pull_request).with(%w(dummy-pkg-b dummy-pkg-c), :dependencies_changed)

      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when a dependency needs to be updated to a different version" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_versions_changed")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "creates a new pull request to supersede the existing one" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when there is a pull request for an overlapping group" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_similar_pr")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "does not attempt to update the other group's pull request" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when the target dependency group is no longer present in the project's config" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_missing_group")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "does nothing, logs a warning and notices an error" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).not_to receive(:create_pull_request)
      expect(mock_service).not_to receive(:close_pull_request)
      expect(mock_service).not_to receive(:update_pull_request)

      expect(Dependabot.logger).to receive(:warn).with(
        "The 'everything-everywhere-all-at-once' group has been removed from the update config."
      )

      expect(mock_service).to receive(:capture_exception).with(
        error: an_instance_of(Dependabot::DependabotError),
        job: job
      )

      group_update_all.perform
    end
  end
end
