# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/group_update_creation"
require "dependabot/dependency_snapshot"
require "dependabot/updater/error_handler"
require "dependabot/job"
require "dependabot/dependency_group"
require "dependabot/dependency"
require "dependabot/update_checkers/base"
require "dependabot/experiments"
require "dependabot/service"

RSpec.describe Dependabot::Updater::GroupUpdateCreation do
  # Create a test class that includes the module to test it
  let(:test_class) do
    Class.new do
      include Dependabot::Updater::GroupUpdateCreation

      attr_reader :dependency_snapshot, :error_handler, :job, :group, :service

      def initialize(dependency_snapshot, error_handler, job, group, service)
        @dependency_snapshot = dependency_snapshot
        @error_handler = error_handler
        @job = job
        @group = group
        @service = service
      end
    end
  end

  let(:service) { instance_double(Dependabot::Service) }
  let(:test_instance) { test_class.new(dependency_snapshot, error_handler, job, group, service) }

  let(:dependency_snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      dependencies: dependencies,
      dependency_files: dependency_files,
      handled_dependencies: [],
      notices: []
    ).tap do |snapshot|
      allow(snapshot).to receive(:add_handled_dependencies)
    end
  end

  let(:error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler).tap do |handler|
      allow(handler).to receive(:handle_job_error)
    end
  end

  let(:job) do
    instance_double(
      Dependabot::Job,
      dependencies: job_dependencies,
      security_advisories_for: security_advisories,
      updating_a_pull_request?: false,
      source: instance_double(Dependabot::Source, directory: "/")
    )
  end

  let(:group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: "test-group",
      dependencies: group_dependencies
    )
  end

  let(:dependencies) do
    [
      instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0"),
      instance_double(Dependabot::Dependency, name: "dep2", version: "2.0.0")
    ]
  end

  let(:group_dependencies) do
    [dependencies.first]
  end

  let(:dependency_files) do
    [instance_double(Dependabot::DependencyFile, name: "Gemfile")]
  end

  let(:job_dependencies) { ["dep1"] }
  let(:security_advisories) { [] }

  let(:checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      dependency: dependencies.first,
      up_to_date?: false,
      conflicting_dependencies: [],
      respond_to?: false
    )
  end

  before do
    # Stub all experiment flags to avoid unexpected argument errors
    allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with("dependency_change_validation")
      .and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:allow_refresh_group_with_all_dependencies)
      .and_return(false)

    # Stub common methods that would be called
    allow(test_instance).to receive_messages(
      prepare_workspace: nil,
      cleanup_workspace: nil
    )
    allow(test_instance).to receive_messages(
      dependency_file_parser: instance_double(Dependabot::FileParsers::Base, parse: dependencies),
      service: instance_double(Dependabot::Service).tap do |service|
        allow(service).to receive(:record_update_job_error)
      end
    )

    # Reset experiments before each test
    Dependabot::Experiments.reset!
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#record_security_update_error_if_applicable" do
    let(:dependency) { dependencies.first }

    context "when enhanced security reporting is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(true)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with("dependency_change_validation")
          .and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:allow_refresh_group_with_all_dependencies)
          .and_return(false)
      end

      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update error when no conflicting dependencies" do
          expect(Dependabot.logger).to receive(:info).with(
            "Security update not possible for #{dependency.name} in group #{group.name}"
          )
          expect(test_instance).to receive(:record_security_update_not_possible_error).with(checker)

          test_instance.record_security_update_error_if_applicable(dependency, checker, group)
        end

        context "when checker has conflicting dependencies with vulnerability explanation" do
          before do
            allow(checker).to receive(:respond_to?).with(:conflicting_dependencies).and_return(true)
            allow(checker).to receive(:conflicting_dependencies).and_return(conflicting_deps)
          end

          let(:conflicting_deps) do
            [{ "explanation" => "Vulnerability fix not available" }]
          end

          it "logs specific explanation and records error" do
            expect(Dependabot.logger).to receive(:info).with(
              "Security update not possible for #{dependency.name} in group #{group.name}: " \
              "Vulnerability fix not available"
            )
            expect(test_instance).to receive(:record_security_update_not_possible_error).with(checker)

            test_instance.record_security_update_error_if_applicable(dependency, checker, group)
          end
        end

        context "when checker has conflicting dependencies without vulnerability explanation" do
          before do
            allow(checker).to receive(:respond_to?).with(:conflicting_dependencies).and_return(true)
            allow(checker).to receive(:conflicting_dependencies).and_return(conflicting_deps)
          end

          let(:conflicting_deps) do
            [{ "dependency_name" => "other_dep", "explanation" => "Regular conflict" }]
          end

          it "logs generic message and records error" do
            expect(Dependabot.logger).to receive(:info).with(
              "Security update not possible for #{dependency.name} in group #{group.name}"
            )
            expect(test_instance).to receive(:record_security_update_not_possible_error).with(checker)

            test_instance.record_security_update_error_if_applicable(dependency, checker, group)
          end
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(test_instance).not_to receive(:record_security_update_not_possible_error)

          test_instance.record_security_update_error_if_applicable(dependency, checker, group)
        end
      end
    end

    context "when enhanced security reporting is disabled" do
      let(:security_advisories) { [{ "id" => "advisory-1" }] }

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(false)
        allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
      end

      it "does not log or record any error even with security advisories" do
        expect(Dependabot.logger).not_to receive(:info)
        expect(test_instance).not_to receive(:record_security_update_not_possible_error)

        test_instance.record_security_update_error_if_applicable(dependency, checker, group)
      end
    end
  end

  describe "#record_security_update_not_found_if_applicable" do
    let(:dependency) { dependencies.first }

    context "when enhanced security reporting is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(true)
      end

      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update not found error" do
          expect(Dependabot.logger).to receive(:info).with(
            "Security update not found for #{dependency.name} in group #{group.name} - " \
            "dependency is up to date but still vulnerable"
          )
          expect(test_instance).to receive(:record_security_update_not_found).with(checker)

          test_instance.record_security_update_not_found_if_applicable(dependency, checker, group)
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(test_instance).not_to receive(:record_security_update_not_found)

          test_instance.record_security_update_not_found_if_applicable(dependency, checker, group)
        end
      end
    end

    context "when enhanced security reporting is disabled" do
      let(:security_advisories) { [{ "id" => "advisory-1" }] }

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(false)
        allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
      end

      it "does not log or record any error even with security advisories" do
        expect(Dependabot.logger).not_to receive(:info)
        expect(test_instance).not_to receive(:record_security_update_not_found)

        test_instance.record_security_update_not_found_if_applicable(dependency, checker, group)
      end
    end
  end

  describe "#record_security_update_ignored_if_applicable" do
    let(:dependency) { dependencies.first }

    context "when enhanced security reporting is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(true)
      end

      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update ignored error" do
          expect(Dependabot.logger).to receive(:info).with(
            "All versions ignored for #{dependency.name} in group #{group.name} but security advisories exist"
          )
          expect(test_instance).to receive(:record_security_update_ignored).with(checker)

          test_instance.record_security_update_ignored_if_applicable(dependency, checker, group)
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(test_instance).not_to receive(:record_security_update_ignored)

          test_instance.record_security_update_ignored_if_applicable(dependency, checker, group)
        end
      end
    end

    context "when enhanced security reporting is disabled" do
      let(:security_advisories) { [{ "id" => "advisory-1" }] }

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(false)
        allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
      end

      it "does not log or record any error even with security advisories" do
        expect(Dependabot.logger).not_to receive(:info)
        expect(test_instance).not_to receive(:record_security_update_ignored)

        test_instance.record_security_update_ignored_if_applicable(dependency, checker, group)
      end
    end
  end

  describe "feature flag behavior in compile_all_dependency_changes_for" do
    before do
      # Stub all the complex methods that would be called during the method
      allow(test_instance).to receive_messages(
        compile_updates_for: [],
        skip_dependency?: false,
        deduce_updated_dependency: nil,
        store_changes: nil,
        record_warning_notices: nil
      )
      allow(Dependabot::Updater::DependencyGroupChangeBatch).to receive(:new).and_return(
        instance_double(
          Dependabot::Updater::DependencyGroupChangeBatch,
          current_dependency_files: dependency_files,
          updated_dependencies: [],
          updated_dependency_files: dependency_files,
          add_updated_dependency: nil,
          merge: nil
        )
      )
      allow(Dependabot::DependencyChange).to receive(:new).and_return(
        instance_double(Dependabot::DependencyChange, all_have_previous_version?: true)
      )
    end

    context "when enhanced security reporting is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(true)
      end

      context "when job dependencies are missing from dependency snapshot" do
        let(:job_dependencies) { %w(dep1 missing_dep) }

        it "records missing dependency error for non-PR updates" do
          expect(error_handler).to receive(:handle_job_error) do |error:|
            expect(error).to be_a(Dependabot::DependencyNotFound)
            expect(error.message).to include("missing_dep")
          end

          test_instance.compile_all_dependency_changes_for(group)
        end

        context "when updating a pull request" do
          before do
            allow(job).to receive(:updating_a_pull_request?).and_return(true)
          end

          it "does not record missing dependency error" do
            expect(error_handler).not_to receive(:handle_job_error)

            test_instance.compile_all_dependency_changes_for(group)
          end
        end
      end

      context "when all job dependencies are present" do
        let(:job_dependencies) { ["dep1"] }

        it "does not record any missing dependency error" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.compile_all_dependency_changes_for(group)
        end
      end
    end

    context "when enhanced security reporting is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(false)
      end

      context "when job dependencies are missing from dependency snapshot" do
        let(:job_dependencies) { %w(dep1 missing_dep) }

        it "does not record missing dependency error" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.compile_all_dependency_changes_for(group)
        end
      end
    end
  end

  describe "feature flag behavior in compile_updates_for" do
    let(:dependency) { dependencies.first }

    before do
      # Stub the complex methods that would be called
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_up_to_date: nil,
        requirements_to_unlock: [],
        log_requirements_for_update: nil
      )
      allow(checker).to receive(:up_to_date?).and_return(false)
    end

    context "when enhanced security reporting is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(true)
      end

      context "when all versions are ignored and dependency has security advisories" do
        before do
          allow(test_instance).to receive(:all_versions_ignored?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "calls record_security_update_ignored_if_applicable" do
          expect(test_instance).to receive(:record_security_update_ignored_if_applicable)
            .with(dependency, checker, group)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end

      context "when dependency is up to date and has security advisories" do
        before do
          allow(checker).to receive(:up_to_date?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "calls record_security_update_not_found_if_applicable" do
          expect(test_instance).to receive(:record_security_update_not_found_if_applicable)
            .with(dependency, checker, group)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end
    end

    context "when enhanced security reporting is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enhanced_grouped_security_error_reporting)
          .and_return(false)
      end

      context "when all versions are ignored and dependency has security advisories" do
        before do
          allow(test_instance).to receive(:all_versions_ignored?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "does not log or record any error even with security advisories" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(test_instance).not_to receive(:record_security_update_ignored)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end

      context "when dependency is up to date and has security advisories" do
        before do
          allow(checker).to receive(:up_to_date?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "does not log or record any error even with security advisories" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(test_instance).not_to receive(:record_security_update_not_found)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end
    end
  end
end
