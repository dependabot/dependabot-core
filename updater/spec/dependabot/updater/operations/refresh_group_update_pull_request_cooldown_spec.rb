# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_group_update_pull_request"
require "dependabot/update_checkers/cooldown_calculation"

require "dependabot/docker"

RSpec.describe Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest do
  subject(:refresh_group) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: instance_double(Dependabot::Updater::ErrorHandler)
    )
  end

  let(:mock_service) do
    instance_double(
      Dependabot::Service,
      increment_metric: nil,
      record_update_job_error: nil,
      create_pull_request: nil,
      update_pull_request: nil,
      close_pull_request: nil,
      record_update_job_warning: nil,
      record_ecosystem_meta: nil,
      record_cooldown_meta: nil
    )
  end

  let(:job_definition) do
    definition = job_definition_fixture("docker/version_updates/group_update_refresh")
    definition["job"]["existing-group-pull-requests"][0]["dependencies"][0]["directory"] = pr_directory
    definition
  end
  let(:pr_directory) { "/" }

  let(:job) { Dependabot::Job.new_update_job(job_id: "1", job_definition: job_definition) }

  let(:dependency_snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      fetched_files: Dependabot::FetchedFiles.new(base_commit_sha: "mock-sha", dependency_files: dependency_files)
    )
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Dockerfile",
        directory: "/",
        content: "FROM python:3.14-alpine@sha256:#{'a' * 64}\n"
      )
    ]
  end

  let(:deferred_by_cooldown) { true }

  before do
    deferred = deferred_by_cooldown
    allow_any_instance_of(Dependabot::Docker::UpdateChecker).to receive(:latest_version).and_return("3.14-alpine") # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Dependabot::Docker::UpdateChecker).to receive(:up_to_date?) do |checker| # rubocop:disable RSpec/AnyInstance
      Dependabot::UpdateCheckers::CooldownCalculation.mark_update_deferred(checker.dependency) if deferred
      true
    end
  end

  describe "#perform" do
    context "when the only newer digest is held back by cooldown" do
      it "keeps the existing pull request open" do
        expect(mock_service).not_to receive(:close_pull_request)
        expect(mock_service).not_to receive(:create_pull_request)

        refresh_group.perform
      end
    end

    context "when nothing was deferred by cooldown" do
      let(:deferred_by_cooldown) { false }

      it "closes the pull request" do
        expect(mock_service).to receive(:close_pull_request).with(["python"], :update_no_longer_possible)

        refresh_group.perform
      end
    end

    context "when the existing pull request is for a different directory" do
      let(:pr_directory) { "/other" }

      it "closes the pull request" do
        expect(mock_service).to receive(:close_pull_request).with(["python"], :update_no_longer_possible)

        refresh_group.perform
      end
    end
  end
end
