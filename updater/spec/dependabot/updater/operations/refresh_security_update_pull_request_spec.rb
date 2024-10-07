# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_security_update_pull_request"
require "dependabot/dependency_change_builder"
require "dependabot/notices"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:perform) { refresh_security_update_pull_request.perform }

  let(:refresh_security_update_pull_request) do
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
    allow(Dependabot::Experiments).to receive(:enabled?).with(:bundler_v1_unsupported_error).and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?).with(:add_deprecation_warn_to_pr_message).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?).with(:existing_pr_version_match).and_return(true)

    allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).and_return(stub_update_checker_class)
    allow(Dependabot::DependencyChangeBuilder)
      .to receive(:create_from)
      .and_return(stub_dependency_change)
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
        allow(refresh_security_update_pull_request).to receive(:check_and_update_pull_request).and_raise(error)
      end

      it "handles the error with the error handler" do
        expect(mock_error_handler).to receive(:handle_dependency_error).with(error: error, dependency: dependency)
        perform
      end
    end

    context "when no error occurs" do
      before do
        allow(refresh_security_update_pull_request).to receive(:check_and_update_pull_request)
      end

      it "does not handle any error" do
        expect(mock_error_handler).not_to receive(:handle_dependency_error)
        perform
      end
    end

    context "when package manager version is unsupported" do
      let(:package_manager_version) { "1" }
      let(:error) { Dependabot::ToolVersionNotSupported.new("bundler", "1", "v2.*, v3.*") }

      before do
        allow(refresh_security_update_pull_request).to receive(:check_and_update_pull_request).and_raise(error)
      end

      it "handles the ToolVersionNotSupported error with the error handler" do
        expect(mock_error_handler).to receive(:handle_dependency_error).with(error: error, dependency: dependency)
        perform
      end
    end
  end

  describe "#check_and_update_pull_request" do
    before do
      allow(dependency).to receive(:all_versions).and_return(["4.0.0", "4.1.0", "4.2.0"])
      allow(job).to receive(:package_manager).and_return("bundler")
    end

    context "when the update is not allowed" do
      before do
        allow(stub_update_checker).to receive(:up_to_date?).and_return(true)
        allow(job).to receive_messages(allowed_update?: false, dependencies: ["dummy-pkg-a"])
      end

      it "does not create a pull request" do
        expect(refresh_security_update_pull_request).not_to receive(:create_pull_request)
        refresh_security_update_pull_request.send(:check_and_update_pull_request, [dependency])
      end
    end

    context "when the update is allowed" do
      before do
        allow(stub_update_checker).to receive_messages(
          up_to_date?: false,
          latest_version: Dependabot::Version.new("4.0.1"),
          requirements_unlocked_or_can_be?: true
        )
        allow(job).to receive_messages(allowed_update?: true, dependencies: ["dummy-pkg-a"])
      end

      it "checks if a pull request already exists" do
        allow(refresh_security_update_pull_request).to receive(:existing_pull_request).and_return(true)
        expect(refresh_security_update_pull_request).to receive(:update_pull_request)
        refresh_security_update_pull_request.send(:check_and_update_pull_request, [dependency])
      end

      context "when pull request does not already exist" do
        before do
          allow(job).to receive(:existing_pull_requests).and_return([
            [
              {
                "dependency-name" => "dummy-pkg-a",
                "dependency-version" => "2.0.0"
              }
            ]
          ])
          allow(refresh_security_update_pull_request).to receive(:check_and_update_pull_request).and_call_original
        end

        it "creates a pull request with deprecation notice" do
          allow(Dependabot::Notice).to receive(:generate_pm_deprecation_notice).and_return([{
            mode: "WARN",
            type: "bundler_deprecated_warn",
            package_manager_name: "bundler",
            title: "Package manager deprecation notice",
            description: "Dependabot will stop supporting `bundler v1`!\n" \
                         "\n\nPlease upgrade to one of the following versions: `v2`, or `v3`.\n",
            show_in_pr: true,
            show_alert: true
          }])
          expect(refresh_security_update_pull_request).to receive(:create_pull_request)
          refresh_security_update_pull_request.send(:check_and_update_pull_request, [dependency])
        end
      end
    end
  end
end
