# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_version_update_pull_request"
require "dependabot/dependency_change_builder"
require "dependabot/package_manager"
require "dependabot/notices"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:perform) { refresh_version_update_pull_request.perform }

  let(:refresh_version_update_pull_request) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(Dependabot::Service, create_pull_request: nil, update_pull_request: nil, close_pull_request: nil)
  end
  let(:mock_error_handler) { instance_double(Dependabot::Updater::ErrorHandler) }

  let(:job_definition) do
    job_definition_fixture("bundler/version_updates/pull_request_simple")
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

  let(:package_manager) do
    DummyPkgHelpers::StubPackageManager.new(
      name: "bundler",
      version: package_manager_version,
      deprecated_versions: deprecated_versions,
      supported_versions: supported_versions
    )
  end

  let(:package_manager_version) { "1" }
  let(:supported_versions) { %w(2 3) }
  let(:deprecated_versions) { %w(1) }

  let(:job_definition_with_fetched_files) do
    job_definition.merge({
      "base_commit_sha" => "mock-sha",
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    })
  end

  let(:dependency_files) do
    original_bundler_files(fixture: "bundler_simple")
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "4.0.0",
      requirements: [{
        file: "Gemfile",
        requirement: "~> 4.0.0",
        groups: ["default"],
        source: nil
      }],
      package_manager: "bundler",
      metadata: { all_versions: ["4.0.0"] }
    )
  end

  let(:stub_update_checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      vulnerable?: true,
      latest_version: "2.3.0",
      version_class: Gem::Version,
      lowest_resolvable_security_fix_version: "2.3.0",
      lowest_security_fix_version: "2.0.0",
      conflicting_dependencies: [],
      up_to_date?: false,
      updated_dependencies: [dependency],
      dependency: dependency,
      requirements_unlocked_or_can_be?: true,
      can_update?: true
    )
  end

  let(:stub_update_checker_class) do
    class_double(Dependabot::Bundler::UpdateChecker, new: stub_update_checker)
  end

  let(:stub_dependency_change) do
    instance_double(
      Dependabot::DependencyChange,
      updated_dependencies: [dependency],
      should_replace_existing_pr?: false,
      grouped_update?: false,
      matches_existing_pr?: false,
      notices: []
    )
  end

  before do
    allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).and_return(stub_update_checker_class)
    allow(Dependabot::DependencyChangeBuilder)
      .to receive(:create_from)
      .and_return(stub_dependency_change)
    allow(dependency_snapshot).to receive(:package_manager).and_return(package_manager)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#perform" do
    before do
      allow(dependency_snapshot).to receive(:job_dependencies).and_return([dependency])
      allow(job).to receive(:package_manager).and_return("bundler")
    end

    context "when an error occurs" do
      let(:error) { StandardError.new("error") }

      before do
        allow(refresh_version_update_pull_request).to receive(:check_and_update_pull_request).and_raise(error)
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
      end

      it "handles the error with the error handler" do
        expect(mock_error_handler).to receive(:handle_dependency_error).with(error: error, dependency: dependency)
        perform
      end
    end

    context "when no error occurs" do
      before do
        allow(refresh_version_update_pull_request).to receive(:check_and_update_pull_request)
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
      end

      it "does not handle any error" do
        expect(mock_error_handler).not_to receive(:handle_dependency_error)
        perform
      end
    end
  end

  describe "#check_and_update_pull_request" do
    before do
      allow(dependency)
        .to receive(:all_versions).and_return(["4.0.0", "4.1.0", "4.2.0"])
      allow(job).to receive(:package_manager).and_return("bundler")
    end

    context "when job dependencies are zero or do not match parsed dependencies" do
      before do
        allow(job).to receive(:dependencies).and_return([])
      end

      it "closes the pull request with reason :dependency_removed" do
        expect(refresh_version_update_pull_request).to receive(
          :close_pull_request
        ).with(reason: :dependency_removed)
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end

    context "when all versions are ignored" do
      before do
        allow(stub_update_checker).to receive(:up_to_date?).and_return(false)
        allow(refresh_version_update_pull_request).to receive(
          :all_versions_ignored?
        ).and_return(true)
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
      end

      it "does not create or update a pull request" do
        expect(refresh_version_update_pull_request).not_to receive(
          :create_pull_request
        )
        expect(refresh_version_update_pull_request).not_to receive(
          :update_pull_request
        )
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end

    context "when checker is up to date" do
      before do
        allow(stub_update_checker).to receive(:up_to_date?).and_return(true)
        allow(refresh_version_update_pull_request).to receive(
          :all_versions_ignored?
        ).and_return(false)
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
      end

      it "closes the pull request with reason :up_to_date" do
        expect(refresh_version_update_pull_request).to receive(
          :close_pull_request
        ).with(reason: :up_to_date)
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end

    context "when requirements update is not possible" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: false
        )
        allow(stub_update_checker).to receive(
          :can_update?
        ).with(requirements_to_unlock: :none).and_return(false)
        allow(refresh_version_update_pull_request).to receive(
          :all_versions_ignored?
        ).and_return(false)
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
      end

      it "closes the pull request with reason :update_no_longer_possible" do
        expect(refresh_version_update_pull_request).to receive(
          :close_pull_request
        ).with(reason: :update_no_longer_possible)
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end

    context "when dependencies have changed" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true,
          updated_dependencies: [dependency]
        )
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
        allow(refresh_version_update_pull_request).to receive(:all_versions_ignored?).and_return(false)
        allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_return(stub_dependency_change)
      end

      it "closes the pull request with reason :dependency_removed" do
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-b"])
        expect(refresh_version_update_pull_request).to receive(:close_pull_request).with(reason: :dependency_removed)
        refresh_version_update_pull_request.send(:check_and_update_pull_request, [dependency])
      end
    end

    context "when an existing pull request matches the dependencies" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true,
          updated_dependencies: [dependency]
        )
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
        allow(Dependabot::DependencyChangeBuilder).to receive(
          :create_from
        ).and_return(stub_dependency_change)
        allow(refresh_version_update_pull_request).to receive_messages(
          all_versions_ignored?: false,
          existing_pull_request: true
        )
      end

      it "updates the pull request" do
        expect(refresh_version_update_pull_request).to receive(
          :update_pull_request
        ).with(stub_dependency_change)
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end

    context "when no existing pull request matches the dependencies" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true
        )
        allow(job).to receive(:dependencies).and_return(["dummy-pkg-a"])
        allow(Dependabot::DependencyChangeBuilder).to receive(
          :create_from
        ).and_return(stub_dependency_change)
        allow(refresh_version_update_pull_request).to receive_messages(
          all_versions_ignored?: false, existing_pull_request: false
        )
      end

      it "creates a new pull request" do
        expect(refresh_version_update_pull_request).to receive(
          :create_pull_request
        ).with(stub_dependency_change)
        refresh_version_update_pull_request.send(
          :check_and_update_pull_request, [dependency]
        )
      end
    end
  end
end
