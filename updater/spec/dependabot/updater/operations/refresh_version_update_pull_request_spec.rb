# typed: true
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"


require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_version_update_pull_request"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:version_update_all) do
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
    result = Dependabot::Job.new_update_job(
      job_id: "1558782000",
      job_definition: job_definition_with_fetched_files
    )
    result.source.directory = directory
    result.source.directories = directories

    result
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

  before do
    stub_rubygems_calls
    Dependabot::Experiments.register("globs", false)
  end

  context "when a single item is in directories" do
    let(:directory) { nil }
    let(:directories) { ["/"] }

    let(:job_definition) { job_definition_fixture("bundler/version_updates/group_update_refresh") }

    let(:dependency_files) { original_bundler_files }

    it "populates directory" do
      version_update_all.to_s
      expect(job.source.directory).to eql("/")
    end
  end
end
