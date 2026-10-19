# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "dependabot/dependency_snapshot"
require "dependabot/dependency_change_builder"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_security_update_pull_request"
require "dependabot/bundler"

# Sorbet fixture signatures must stay beside their lets.
# rubocop:disable-next RSpec/ScatteredLet
RSpec.describe Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest do
  extend T::Sig
  include DummyPkgHelpers

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { original_bundler_files(fixture: "bundler_simple") }

  sig { returns(String) }
  let(:allowed_dependency_type) { "all" }

  sig { returns(T::Boolean) }
  let(:vulnerable_production) { true }

  sig { returns(Dependabot::Job) }
  let(:job) do
    definition = job_definition_fixture("bundler/version_updates/pull_request_simple")
    definition["job"].merge!(
      "allowed-updates" => [{ "dependency-type" => allowed_dependency_type, "update-type" => "security" }],
      "dependencies" => ["dummy-pkg-a"],
      "security-updates-only" => true,
      "updating-a-pull-request" => true,
      "existing-pull-requests" => [],
      "security-advisories" => [{
        "dependency-name" => "dummy-pkg-a",
        "affected-versions" => [">= 2.0.0, < 2.1.4"],
        "patched-versions" => [],
        "unaffected-versions" => []
      }]
    )
    Dependabot::Job.new_update_job(job_id: "123", job_definition: definition)
  end

  sig { returns(Dependabot::Dependency) }
  let(:safe_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "1.1.12",
      requirements: [],
      package_manager: "bundler",
      subdependency_metadata: [{ production: true }]
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:vulnerable_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "2.1.2",
      requirements: [],
      package_manager: "bundler",
      subdependency_metadata: [{ production: vulnerable_production }]
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:combined_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "1.1.12",
      requirements: [],
      package_manager: "bundler",
      metadata: { all_versions: [safe_dependency, vulnerable_dependency] }
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:updated_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "2.1.4",
      previous_version: "2.1.2",
      requirements: [],
      previous_requirements: [],
      package_manager: "bundler"
    )
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      job_dependencies: [combined_dependency],
      dependency_files: dependency_files,
      base_commit_sha: "mock-sha",
      notices: [],
      ecosystem: nil
    )
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:safe_checker) do
    instance_double(Dependabot::UpdateCheckers::Base, version_class: Gem::Version, vulnerable?: false)
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:vulnerable_checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      dependency: vulnerable_dependency,
      version_class: Gem::Version,
      vulnerable?: true,
      latest_version: Gem::Version.new("5.0.12"),
      up_to_date?: false,
      requirements_unlocked_or_can_be?: true,
      can_update?: true,
      updated_dependencies: [updated_dependency]
    )
  end

  sig { returns(RSpec::Mocks::ClassVerifyingDouble) }
  let(:checker_class) { class_double(Dependabot::Bundler::UpdateChecker) }

  sig { returns(Dependabot::DependencyChange) }
  let(:dependency_change) do
    Dependabot::DependencyChange.new(
      job: job,
      updated_dependencies: [updated_dependency],
      updated_dependency_files: []
    )
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:service) do
    instance_double(Dependabot::Service, record_ecosystem_meta: nil, increment_metric: nil)
  end

  sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
  let(:error_handler) { instance_double(Dependabot::Updater::ErrorHandler) }

  before do
    allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).with("bundler").and_return(checker_class)
    allow(checker_class).to receive(:new).with(hash_including(dependency: safe_dependency)).and_return(safe_checker)
    allow(checker_class).to receive(:new)
      .with(hash_including(dependency: vulnerable_dependency)).and_return(vulnerable_checker)
  end

  it "refreshes the vulnerable installed version rather than the safe combined version" do
    allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(dependency_change)
    expect(error_handler).not_to receive(:handle_dependency_error)
    expect(service).to receive(:create_pull_request).with(dependency_change, "mock-sha")

    described_class.new(service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler).perform

    expect(Dependabot::DependencyChangeBuilder).to have_received(:create_from).with(
      job: job,
      dependency_files: dependency_files,
      updated_dependencies: [updated_dependency],
      change_source: vulnerable_dependency,
      notices: []
    )
    expect(checker_class).to have_received(:new).with(hash_including(dependency: vulnerable_dependency)).twice
  end

  context "when only production updates are allowed" do
    sig { returns(String) }
    let(:allowed_dependency_type) { "production" }

    it "refreshes a vulnerable production copy" do
      allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(dependency_change)
      expect(error_handler).not_to receive(:handle_dependency_error)
      expect(service).to receive(:create_pull_request).with(dependency_change, "mock-sha")

      described_class.new(
        service: service,
        job: job,
        dependency_snapshot: snapshot,
        error_handler: error_handler
      ).perform
    end

    context "when only the development copy is vulnerable" do
      sig { returns(T::Boolean) }
      let(:vulnerable_production) { false }

      it "closes the pull request without updating the excluded copy" do
        expect(job.allowed_update?(combined_dependency)).to be(true)
        expect(job.allowed_update?(vulnerable_dependency)).to be(false)
        expect(error_handler).not_to receive(:handle_dependency_error)
        expect(service).to receive(:close_pull_request).with(["dummy-pkg-a"], :up_to_date)
        expect(service).not_to receive(:create_pull_request)
        expect(vulnerable_checker).not_to receive(:updated_dependencies)

        described_class.new(
          service: service,
          job: job,
          dependency_snapshot: snapshot,
          error_handler: error_handler
        ).perform
      end
    end
  end
end
