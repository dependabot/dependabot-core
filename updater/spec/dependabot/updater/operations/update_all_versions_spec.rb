# typed: true
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/service"
require "dependabot/dependency_snapshot"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/update_all_versions"
require_relative "empty_return_update_checker"

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

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directory: "/",
      branch: nil,
      api_endpoint: "https://api.github.com/",
      hostname: "github.com"
    )
  end

  let(:job) do
    instance_double(Dependabot::Job,
                    package_manager: "bundler",
                    repo_contents_path: nil,
                    credentials: [],
                    reject_external_code?: false,
                    source: source,
                    dependency_groups: [],
                    allowed_update?: true,
                    experiments: { large_hadron_collider: true },
                    ignore_conditions_for: [">= 0"],
                    security_advisories_for: [],
                    log_ignore_conditions_for: [],
                    existing_pull_requests: [],
                    requirements_update_strategy: nil)
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

  let(:dependency_files) do
    original_bundler_files
  end

  let(:mock_error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler)
  end

  before do
    allow(Dependabot.logger).to receive(:info)
    allow_any_instance_of(Dependabot::Bundler::UpdateChecker)
      .to receive(:latest_version).and_return("")
    allow_any_instance_of(Dependabot::Bundler::UpdateChecker)
      .to receive(:can_update?).and_return(true)
    allow_any_instance_of(Dependabot::Bundler::UpdateChecker)
      .to receive(:up_to_date?).and_return(false)
    allow_any_instance_of(Dependabot::Bundler::UpdateChecker)
      .to receive(:updated_dependencies).and_return([])

    allow_any_instance_of(Dependabot::Bundler::FileUpdater)
      .to receive(:parse).and_return([])
    allow_any_instance_of(Dependabot::Bundler::FileUpdater)
      .to receive(:check_required_files)
  end

  after do
    Dependabot::Experiments.reset!
  end

  context "when updatedDeps is empty" do
    let(:job_definition) do
      {
        "type" => "update",
        "package_manager" => "bundler",
        "target_dependency" => "business",
        "updatedDeps" => []
      }
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        previous_version: dependency_previous_version,
        requirements: requirements,
        previous_requirements: previous_requirements,
        package_manager: "bundler"
      )
    end

    let(:dependency_name) { "business" }
    let(:dependency_version) { "1.5.0" }
    let(:dependency_previous_version) { "1.5.0" }
    let(:requirements) do
      [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
    end
    let(:previous_requirements) do
      [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
    end

    it "does not update any dependencies" do
      expect { subject.send(:check_and_create_pull_request, dependency) }.to raise_error(
        "Dependabot found some dependency requirements to unlock, yet it failed to update any dependencies"
      )
    end
  end
end
