# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_snapshot"
require "dependabot/dependency_change_builder"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_security_update_pull_request"
require "dependabot/bun"
require "dependabot/cargo"
require "dependabot/npm_and_yarn"

# Sorbet fixture signatures must stay beside their lets.
# rubocop:disable-next RSpec/ScatteredLet
RSpec.describe Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    [Dependabot::DependencyFile.new(name: "package.json", content: '{"name":"refresh-security-fixture"}')]
  end

  sig { returns(String) }
  let(:package_manager) { "npm_and_yarn" }

  sig { returns(String) }
  let(:allowed_dependency_type) { "all" }

  sig { returns(T::Boolean) }
  let(:vulnerable_production) { true }

  sig { returns(String) }
  let(:affected_versions) { ">= 2.0.0 < 2.1.4" }

  sig { returns(Dependabot::Job) }
  let(:job) do
    definition = job_definition_fixture("bundler/version_updates/pull_request_simple")
    definition["job"].merge!(
      "package-manager" => package_manager,
      "allowed-updates" => [{ "dependency-type" => allowed_dependency_type, "update-type" => "security" }],
      "dependencies" => ["dummy-pkg-a"],
      "security-updates-only" => true,
      "updating-a-pull-request" => true,
      "existing-pull-requests" => [],
      "security-advisories" => [{
        "dependency-name" => "dummy-pkg-a",
        "affected-versions" => [affected_versions],
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
      package_manager: package_manager,
      subdependency_metadata: [{ production: true }]
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:vulnerable_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "2.1.2",
      requirements: [],
      package_manager: package_manager,
      subdependency_metadata: [{ production: vulnerable_production }]
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:combined_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "1.1.12",
      requirements: [],
      package_manager: package_manager,
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
      package_manager: package_manager
    )
  end

  sig { returns(T::Array[Dependabot::Dependency]) }
  let(:updated_dependencies) { [updated_dependency] }

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
      updated_dependencies: updated_dependencies
    )
  end

  sig { returns(RSpec::Mocks::ClassVerifyingDouble) }
  let(:checker_class) { class_double(Dependabot::NpmAndYarn::UpdateChecker) }

  sig { returns(Dependabot::DependencyChange) }
  let(:dependency_change) do
    Dependabot::DependencyChange.new(
      job: job,
      updated_dependencies: updated_dependencies,
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
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).with(package_manager).and_return(checker_class)
    allow(checker_class).to receive(:new).with(hash_including(dependency: safe_dependency)).and_return(safe_checker)
    allow(checker_class).to receive(:new)
      .with(hash_including(dependency: vulnerable_dependency)).and_return(vulnerable_checker)
  end

  context "when the experiment is disabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
      allow(checker_class).to receive(:new)
        .with(hash_including(dependency: combined_dependency)).and_return(safe_checker)
      allow(safe_checker).to receive_messages(up_to_date?: true, latest_version: Gem::Version.new("5.0.12"))
    end

    it "checks the combined dependency without selecting a vulnerable copy" do
      expect(error_handler).not_to receive(:handle_dependency_error)
      expect(service).to receive(:close_pull_request).with(["dummy-pkg-a"], :up_to_date)

      described_class.new(
        service: service,
        job: job,
        dependency_snapshot: snapshot,
        error_handler: error_handler
      ).perform

      expect(checker_class).not_to have_received(:new).with(hash_including(dependency: vulnerable_dependency))
    end
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

    context "when a vulnerable development copy precedes a vulnerable production copy" do
      sig { returns(Dependabot::Dependency) }
      let(:development_dependency) do
        Dependabot::Dependency.new(
          name: "dummy-pkg-a",
          version: "2.1.1",
          requirements: [],
          package_manager: package_manager,
          subdependency_metadata: [{ production: false }]
        )
      end

      sig { returns(Dependabot::Dependency) }
      let(:combined_dependency) do
        Dependabot::Dependency.new(
          name: "dummy-pkg-a",
          version: "2.1.1",
          requirements: [],
          package_manager: package_manager,
          metadata: { all_versions: [development_dependency, vulnerable_dependency] }
        )
      end

      before do
        allow(checker_class).to receive(:new)
          .with(hash_including(dependency: development_dependency)).and_return(vulnerable_checker)
      end

      it "refreshes the eligible production copy instead of closing the pull request" do
        expect(job.current_version_vulnerable?(development_dependency)).to be(true)
        expect(job.allowed_update?(development_dependency)).to be(false)
        expect(job.allowed_update?(vulnerable_dependency)).to be(true)
        allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(dependency_change)
        expect(error_handler).not_to receive(:handle_dependency_error)
        expect(service).not_to receive(:close_pull_request)
        expect(service).to receive(:create_pull_request).with(dependency_change, "mock-sha")

        described_class.new(
          service: service,
          job: job,
          dependency_snapshot: snapshot,
          error_handler: error_handler
        ).perform

        expect(Dependabot::DependencyChangeBuilder).to have_received(:create_from).with(
          job: job,
          dependency_files: dependency_files,
          updated_dependencies: [updated_dependency],
          change_source: vulnerable_dependency,
          notices: []
        )
      end
    end
  end

  context "with Bun installed versions" do
    sig { returns(String) }
    let(:package_manager) { "bun" }

    sig { returns(RSpec::Mocks::ClassVerifyingDouble) }
    let(:checker_class) { class_double(Dependabot::Bun::UpdateChecker) }

    it "refreshes the vulnerable installed copy" do
      allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(dependency_change)
      expect(error_handler).not_to receive(:handle_dependency_error)
      expect(service).to receive(:create_pull_request).with(dependency_change, "mock-sha")

      described_class.new(
        service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler
      ).perform

      expect(checker_class).to have_received(:new).with(hash_including(dependency: vulnerable_dependency)).twice
    end
  end

  context "with multiple vulnerable Cargo locked versions" do
    sig { returns(String) }
    let(:package_manager) { "cargo" }

    sig { returns(String) }
    let(:affected_versions) { ">= 2.0.0, < 2.1.4" }

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      [Dependabot::DependencyFile.new(
        name: "Cargo.toml",
        content: "[package]\nname = \"refresh-security-fixture\"\n"
      )]
    end

    sig { returns(RSpec::Mocks::ClassVerifyingDouble) }
    let(:checker_class) { class_double(Dependabot::Cargo::UpdateChecker) }

    sig { returns(Dependabot::Dependency) }
    let(:first_locked_dependency) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        version: "2.1.1",
        requirements: [],
        package_manager: package_manager,
        metadata: { cargo_package_source: "registry+https://github.com/rust-lang/crates.io-index" }
      )
    end

    sig { returns(Dependabot::Dependency) }
    let(:vulnerable_dependency) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        version: "2.1.2",
        requirements: [],
        package_manager: package_manager,
        metadata: { cargo_package_source: "registry+https://github.com/rust-lang/crates.io-index" }
      )
    end

    sig { returns(Dependabot::Dependency) }
    let(:combined_dependency) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        version: "2.1.1",
        requirements: [],
        package_manager: package_manager,
        metadata: { all_versions: [first_locked_dependency, vulnerable_dependency] }
      )
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    let(:updated_dependencies) do
      [
        Dependabot::Dependency.new(
          name: "dummy-pkg-a",
          version: "2.1.4",
          previous_version: "2.1.1",
          requirements: [],
          previous_requirements: [],
          package_manager: package_manager
        ),
        updated_dependency
      ]
    end

    before do
      allow(vulnerable_checker).to receive(:dependency).and_return(combined_dependency)
      allow(checker_class).to receive(:new)
        .with(hash_including(dependency: equal(combined_dependency))).and_return(vulnerable_checker)
    end

    it "retains the aggregate checker and both locked-version updates" do
      allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(dependency_change)
      expect(error_handler).not_to receive(:handle_dependency_error)
      expect(service).not_to receive(:close_pull_request)
      expect(service).to receive(:create_pull_request).with(dependency_change, "mock-sha")

      described_class.new(
        service: service, job: job, dependency_snapshot: snapshot, error_handler: error_handler
      ).perform

      expect(checker_class).to have_received(:new).with(hash_including(dependency: equal(combined_dependency))).once
      expect(Dependabot::DependencyChangeBuilder).to have_received(:create_from).with(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: equal(combined_dependency),
        notices: []
      )
    end
  end

  context "when only the development copy is vulnerable" do
    sig { returns(String) }
    let(:allowed_dependency_type) { "production" }

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
