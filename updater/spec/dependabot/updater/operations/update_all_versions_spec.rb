# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/update_all_versions"
require "dependabot/dependency_change_builder"
require "dependabot/environment"
require "dependabot/ecosystem"
require "dependabot/notices"
require "dependabot/notices_helpers"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::UpdateAllVersions do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:perform) { update_all_versions.perform }

  let(:update_all_versions) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(
      Dependabot::Service,
      increment_metric: nil,
      record_update_job_error: nil,
      create_pull_request: nil,
      record_update_job_warning: nil,
      record_ecosystem_meta: nil
    )
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

  let(:ecosystem) do
    Dependabot::Ecosystem.new(
      name: "bundler",
      package_manager: package_manager
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

  let(:package_manager_version) { "2" }
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
    class_double(
      Dependabot::Bundler::UpdateChecker,
      new: stub_update_checker
    )
  end

  let(:stub_dependency_change) do
    instance_double(
      Dependabot::DependencyChange,
      updated_dependencies: [dependency],
      updated_dependency_files: dependency_files,
      should_replace_existing_pr?: false,
      grouped_update?: false,
      matches_existing_pr?: false
    )
  end

  let(:warning_deprecation_notice) do
    Dependabot::Notice.new(
      mode: "WARN",
      type: "bundler_deprecated_warn",
      package_manager_name: "bundler",
      title: "Package manager deprecation notice",
      description: "Dependabot will stop supporting `bundler v1`!\n" \
                   "\n\nPlease upgrade to one of the following versions: `v2`, or `v3`.\n",
      show_in_pr: true,
      show_alert: true
    )
  end

  before do
    allow(Dependabot::UpdateCheckers).to receive(
      :for_package_manager
    ).and_return(stub_update_checker_class)
    allow(Dependabot::DependencyChangeBuilder).to receive(
      :create_from
    ).and_return(stub_dependency_change)
    allow(dependency_snapshot).to receive_messages(ecosystem: ecosystem, notices: [
      warning_deprecation_notice
    ])
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#perform" do
    before do
      allow(dependency_snapshot).to receive(
        :dependencies
      ).and_return([dependency])
      allow(job).to receive(:package_manager).and_return("bundler")
    end

    context "when an error occurs" do
      let(:error) { StandardError.new("error") }

      before do
        allow(update_all_versions).to receive(
          :check_and_create_pull_request
        ).and_raise(error)
      end

      it "handles the error with the error handler" do
        expect(mock_error_handler).to receive(
          :handle_dependency_error
        ).with(error: error, dependency: dependency)
        perform
      end
    end

    context "when no error occurs" do
      before do
        allow(update_all_versions).to receive(
          :check_and_create_pull_request
        )
      end

      it "does not handle any error" do
        expect(mock_error_handler).not_to receive(
          :handle_dependency_error
        )
        perform
      end
    end

    context "when package manager version is deprecated" do
      let(:package_manager_version) { "1" }

      it "creates a pull request" do
        expect(update_all_versions).to receive(:check_and_create_pull_request).with(dependency).and_call_original
        expect(mock_service).to receive(:record_update_job_warning).with(
          warn_type: warning_deprecation_notice.type,
          warn_title: warning_deprecation_notice.title,
          warn_description: warning_deprecation_notice.description
        )
        expect(update_all_versions).to receive(:create_pull_request).with(stub_dependency_change)
        perform
      end
    end

    context "when package manager version is not deprecated" do
      let(:package_manager_version) { "2" }

      it "creates a pull request" do
        expect(update_all_versions).to receive(:check_and_create_pull_request).with(dependency).and_call_original
        expect(update_all_versions).to receive(:create_pull_request).with(stub_dependency_change)
        perform
      end
    end
  end

  describe "#check_and_create_pull_request" do
    before do
      allow(dependency).to receive(:all_versions).and_return(
        ["4.0.0", "4.1.0", "4.2.0"]
      )
      allow(job).to receive(:package_manager).and_return("bundler")
    end

    context "when checker is up to date" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: true
        )
        allow(update_all_versions).to receive(:all_versions_ignored?).and_return(false)
      end

      it "logs that no update is needed" do
        expect(update_all_versions).to receive(:log_up_to_date).with(dependency)
        update_all_versions.send(:check_and_create_pull_request, dependency)
      end
    end

    context "when a pull request already exists for the latest version" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          latest_version: Gem::Version.new("2.0.1")
        )
        allow(update_all_versions).to receive_messages(
          all_versions_ignored?: false,
          pr_exists_for_latest_version?: true
        )
        allow(job).to receive(
          :existing_pull_requests
        ).and_return([[{
          "dependency-name" => "dummy-pkg-a",
          "dependency-version" => "2.0.1"
        }]])
      end

      it "does not create a pull request" do
        expect(update_all_versions).not_to receive(:create_pull_request)
        update_all_versions.send(:check_and_create_pull_request, dependency)
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
        allow(update_all_versions).to receive(:all_versions_ignored?).and_return(false)
      end

      it "logs that no update is possible" do
        allow(Dependabot.logger).to receive(:info).and_call_original
        expect(Dependabot.logger).to receive(:info).with("Checking if dummy-pkg-a 4.0.0 needs updating").ordered
        expect(Dependabot.logger).to receive(:info).with("No update possible for dummy-pkg-a 4.0.0").ordered

        update_all_versions.send(:check_and_create_pull_request, dependency)
      end
    end

    context "when no dependencies are updated" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true,
          updated_dependencies: []
        )
        allow(update_all_versions).to receive(:all_versions_ignored?).and_return(false)
      end

      it "raises an error" do
        expect do
          update_all_versions.send(:check_and_create_pull_request, dependency)
        end.to raise_error(
          RuntimeError,
          "Dependabot found some dependency requirements to unlock, yet it failed to update any dependencies"
        )
      end
    end

    context "when an existing pull request matches the updated dependencies" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true,
          updated_dependencies: [dependency],
          latest_version: Gem::Version.new("2.0.0")
        )
      end

      it "does not create a pull request" do
        expect(update_all_versions).not_to receive(:create_pull_request)
        update_all_versions.send(:check_and_create_pull_request, dependency)
      end
    end

    context "when no existing pull request matches the updated dependencies" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          requirements_unlocked_or_can_be?: true,
          updated_dependencies: [dependency]
        )
        allow(update_all_versions).to receive_messages(
          all_versions_ignored?: false,
          existing_pull_request: false
        )
        allow(Dependabot::DependencyChangeBuilder).to receive(
          :create_from
        ).and_return(stub_dependency_change)
      end

      it "creates a pull request" do
        expect(update_all_versions).to receive(:create_pull_request).with(
          stub_dependency_change
        )
        update_all_versions.send(:check_and_create_pull_request, dependency)
      end
    end
  end
end
