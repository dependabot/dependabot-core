# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/create_security_update_pull_request"
require "dependabot/dependency_change_builder"
require "dependabot/notices"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::CreateSecurityUpdatePullRequest do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:perform) { create_security_update_pull_request.perform }

  let(:create_security_update_pull_request) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(Dependabot::Service, increment_metric: nil, record_update_job_error: nil, create_pull_request: nil)
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
        file: "package.json",
        requirement: "^4.0.0",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "bundler",
      metadata: { all_versions: ["4.0.0"] }
    )
  end

  let(:dependency_with_transitive_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "2.3.0",
      requirements: [{
        file: "Gemfile",
        requirement: "^2.0.1",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "bundler",
      metadata: { all_versions: [
        Dependabot::Dependency.new(
          name: "dummy-pkg-a",
          requirements: [],
          package_manager: "bundler",
          version: "5.51.2",
          metadata: {}
        ), Dependabot::Dependency.new(
          name: "dummy-pkg-a",
          requirements: [],
          package_manager: "bundler",
          version: "2.3.0",
          metadata: {}
        )
      ] }
    )
  end

  let(:transitive_dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "2.0.1",
      requirements: [],
      package_manager: "bundler"
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

  let(:transitive_stub_update_checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      vulnerable?: true,
      latest_version: "2.3.0",
      version_class: Gem::Version,
      lowest_resolvable_security_fix_version: nil,
      lowest_security_fix_version: "2.3.0",
      conflicting_dependencies: [{
        "explanation" => "dummy-pkg-b@0.2.0 requires dummy-pkg-a@~2.0.1",
        "name" => "dummy-pkg-b",
        "version" => "0.2.0",
        "requirement" => "~2.0.1"
      }],
      up_to_date?: false,
      updated_dependencies: [transitive_dependency],
      dependency: transitive_dependency,
      requirements_unlocked_or_can_be?: false,
      can_update?: false
    )
  end

  let(:stub_update_checker_class) do
    Class.new do
      define_method(:new) do |*_args|
        stub_update_checker
      end
    end
  end

  let(:transitive_stub_update_checker_class) do
    Class.new do
      define_method(:new) do |*_args|
        transitive_stub_update_checker
      end
    end
  end

  let(:concrete_package_manager_class) do
    Class.new(Dependabot::PackageManagerBase) do
      def name
        "bundler"
      end

      def version
        Dependabot::Version.new("1.0.0")
      end

      def deprecated_versions
        [Dependabot::Version.new("1.0.0")]
      end

      def unsupported_versions
        [Dependabot::Version.new("0.9.0")]
      end

      def supported_versions
        [Dependabot::Version.new("1.1.0"), Dependabot::Version.new("2.0.0")]
      end

      def support_later_versions?
        true
      end
    end
  end

  let(:mock_package_manager_instance) { concrete_package_manager_class.new }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).with(:add_deprecation_warn_to_pr_message).and_return(true)

    # Allow for_package_manager to return the stub_update_checker_class
    allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).and_return(stub_update_checker_class)

    # Mock the DependencyChangeBuilder.create_from method
    allow(Dependabot::DependencyChangeBuilder)
      .to receive(:create_from)
      .and_return(instance_double(Dependabot::DependencyChange))

    # Mock the create_pull_request method
    allow(create_security_update_pull_request)
      .to receive(:create_pull_request)

    # Mock the package_manager method in dependency_snapshot
    allow(dependency_snapshot)
      .to receive(:package_manager)
      .and_return(mock_package_manager_instance)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#perform" do
    context "when target_dependencies is empty" do
      before do
        allow(dependency_snapshot)
          .to receive(:job_dependencies).and_return([])
      end

      it "records that no dependencies were found" do
        expect(create_security_update_pull_request)
          .to receive(:record_security_update_dependency_not_found)
        perform
      end
    end

    context "when target_dependencies is not empty" do
      before do
        allow(dependency_snapshot)
          .to receive(:job_dependencies).and_return([dependency])
      end

      it "checks and creates pull requests for each dependency" do
        expect(create_security_update_pull_request)
          .to receive(:check_and_create_pr_with_error_handling).with(dependency)
        perform
      end

      it "calls check_and_create_pull_request with the dependency" do
        allow(create_security_update_pull_request)
          .to receive(:check_and_create_pr_with_error_handling).and_call_original
        expect(create_security_update_pull_request)
          .to receive(:check_and_create_pull_request).with(dependency)
        perform
      end

      it "handles Dependabot::InconsistentRegistryResponse" do
        allow(create_security_update_pull_request)
          .to receive(:check_and_create_pull_request).and_raise(Dependabot::InconsistentRegistryResponse)
        expect(mock_error_handler)
          .to receive(:log_dependency_error).with(
            dependency: dependency,
            error: instance_of(Dependabot::InconsistentRegistryResponse),
            error_type: "inconsistent_registry_response",
            error_detail: anything
          )
        perform
      end

      it "handles StandardError" do
        allow(create_security_update_pull_request)
          .to receive(:check_and_create_pull_request).and_raise(StandardError)
        expect(mock_error_handler)
          .to receive(:handle_dependency_error).with(
            error: instance_of(StandardError),
            dependency: dependency
          )
        perform
      end
    end
  end

  describe "#check_and_create_pull_request" do
    before do
      allow(create_security_update_pull_request)
        .to receive(:update_checker_for).and_return(stub_update_checker)
      allow(dependency)
        .to receive(:all_versions).and_return(["4.0.0", "4.1.0", "4.2.0"])
    end

    context "when the dependency is not vulnerable" do
      before do
        allow(stub_update_checker)
          .to receive(:vulnerable?).and_return(false)
      end

      it "records that no update is needed if the version is correct" do
        allow(stub_update_checker.version_class)
          .to receive(:correct?).with(dependency.version).and_return(true)
        expect(create_security_update_pull_request)
          .to receive(:record_security_update_not_needed_error).with(dependency)
        create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
      end

      it "records that the dependency file is not supported if the version is not correct" do
        allow(stub_update_checker.version_class)
          .to receive(:correct?).with(dependency.version).and_return(false)
        expect(create_security_update_pull_request)
          .to receive(:record_dependency_file_not_supported_error).with(stub_update_checker)
        create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
      end
    end

    context "when the update is allowed" do
      before do
        allow(stub_update_checker)
          .to receive_messages(
            up_to_date?: false,
            latest_version: Dependabot::Version.new("4.0.1"),
            requirements_unlocked_or_can_be?: true
          )
        allow(job)
          .to receive_messages(security_fix?: true, allowed_update?: true)
        allow(job)
          .to receive(:existing_pull_requests).and_return(
            [
              Dependabot::PullRequest.new([
                Dependabot::PullRequest::Dependency.new(
                  name: "dummy-pkg-a", version: "4.0.1"
                )
              ])
            ]
          )
      end

      it "checks if a pull request already exists" do
        expect(create_security_update_pull_request)
          .to receive(:record_pull_request_exists_for_latest_version).with(stub_update_checker)
        create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
      end

      context "when pull request doesn't exists" do
        before do
          allow(job)
            .to receive(:existing_pull_requests).and_return(
              []
            )
        end

        it "creates a pull request without pr notices" do
          expect(create_security_update_pull_request).to receive(:create_pull_request)

          create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
        end

        it "creates a pull request with pr notices" do
          allow(Dependabot::Notice)
            .to receive(:generate_pm_deprecation_notice)
            .with(mock_package_manager_instance)
            .and_return(
              Dependabot::Notice.new(
                mode: "WARN",
                type: "bundler_deprecated_warn",
                package_manager_name: "bundler",
                title: "Package manager deprecation notice",
                description: "Dependabot will stop supporting `bundler v1`!\n" \
                             "Please upgrade to one of the following versions: `v2`, or `v3`.\n",
                markdown: "> [!WARNING]\n> Dependabot will stop supporting `bundler v1`!\n>\n" \
                          "> Please upgrade to one of the following versions: `v2`, or `v3`.\n>\n",
                show_in_pr: true,
                show_in_log: true
              )
            )

          expect(create_security_update_pull_request).to receive(:create_pull_request)

          create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
        end
      end
    end

    context "when the update is not allowed" do
      before do
        allow(stub_update_checker)
          .to receive(:requirements_unlocked_or_can_be?).and_return(false)
        allow(stub_update_checker)
          .to receive(:can_update?).with(requirements_to_unlock: :none).and_return(false)
      end

      it "records that the update is not possible" do
        expect(create_security_update_pull_request)
          .to receive(:record_security_update_not_possible_error).with(stub_update_checker)
        create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
      end
    end

    context "when a transitive dependency conflict occurs" do
      before do
        allow(create_security_update_pull_request)
          .to receive(:update_checker_for).and_return(transitive_stub_update_checker)
        allow(dependency_with_transitive_dependency)
          .to receive(:all_versions).and_return(["5.51.2", "2.0.1", "2.3.0"])
        allow(job)
          .to receive_messages(security_fix?: true, allowed_update?: true)
      end

      it "records the conflict and returns from the function" do
        transitive_stub_update_checker = instance_double(Dependabot::UpdateCheckers::Base)
        allow(transitive_stub_update_checker).to receive(:conflicting_dependencies).and_return([{
          "explanation" => "dummy-pkg-b@0.2.0 requires dummy-pkg-a@~2.0.1",
          "name" => "dummy-pkg-b",
          "version" => "0.2.0",
          "requirement" => "~2.0.1"
        }])

        allow(create_security_update_pull_request)
          .to receive(:check_and_create_pull_request).and_call_original
        allow(create_security_update_pull_request)
          .to receive(:record_security_update_not_possible_error)

        expect(create_security_update_pull_request)
          .to receive(:record_security_update_not_possible_error)

        create_security_update_pull_request.send(:check_and_create_pull_request, dependency_with_transitive_dependency)
      end

      it "does not create a pull request if there is a conflict" do
        allow(transitive_stub_update_checker)
          .to receive(:conflicting_dependencies).and_return([{
            "explanation" => "dummy-pkg-b@0.2.0 requires dummy-pkg-a@~2.0.1",
            "name" => "dummy-pkg-b",
            "version" => "0.2.0",
            "requirement" => "~2.0.1"
          }])
        expect(mock_service).not_to receive(:create_pull_request)
        create_security_update_pull_request.send(:check_and_create_pull_request, transitive_dependency)
      end
    end

    context "when all updates are ignored" do
      before do
        allow(create_security_update_pull_request)
          .to receive(:update_checker_for).and_raise(Dependabot::AllVersionsIgnored)
      end

      it "logs that all updates were ignored and raises an error" do
        expect(Dependabot.logger)
          .to receive(:info).with("All updates for dummy-pkg-a were ignored")
        expect do
          create_security_update_pull_request.send(:check_and_create_pull_request, dependency)
        end.to raise_error(Dependabot::AllVersionsIgnored)
      end
    end
  end
end
