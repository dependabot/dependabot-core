# typed: true
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_snapshot"
require "dependabot/file_fetchers"
require "dependabot/service"
require "dependabot/job"
require "dependabot/updater/operations/update_all_versions"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::UpdateAllVersions do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:update_all_versions) do
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

  let(:job_definition) do
    job_definition_fixture("bundler/version_updates/update_all_simple")
  end

  let(:job_definition_with_fetched_files) do
    job_definition.merge({
      "base_commit_sha" => "mock-sha",
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    })
  end

  let(:dependency_files) do
    original_bundler_files
  end

  let(:mock_error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler)
  end

  before do
    stub_rubygems_calls
  end

  after do
    Dependabot::Experiments.reset!
  end

  context "when doing an update" do
    it "performs a dependency update" do
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group).to be_nil

        # We updated the right dependencies
        expect(dependency_change.updated_dependencies.length).to eql(1)
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(dummy-pkg-b))

        # We updated the right files correctly.
        expect(dependency_change.updated_dependency_files_hash.length).to eql(2)
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      update_all_versions.perform
    end
  end

  context "when the update fails to update the dependencies" do
    before do
      allow_any_instance_of(Dependabot::Bundler::UpdateChecker).to receive(:updated_dependencies).and_return([])
    end

    it "logs an error" do
      expect(mock_error_handler).to receive(:handle_dependency_error) do |error:, dependency:|
        expect(error.message).to match(/it failed to update any dependencies/)
        expect(dependency.name).to eql("dummy-pkg-b")
      end

      update_all_versions.perform
    end
  end
end
