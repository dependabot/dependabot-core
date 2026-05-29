# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/errors"
require "dependabot/job"
require "dependabot/service"
require "dependabot/shared_helpers"
require "dependabot/updater/error_handler"

RSpec.describe Dependabot::Updater::ErrorHandler do
  subject(:error_handler) do
    described_class.new(
      service: mock_service,
      job: mock_job
    )
  end

  let(:mock_service) do
    instance_double(Dependabot::Service).tap do |service|
      allow(service).to receive(:increment_metric)
    end
  end

  let(:mock_job) do
    instance_double(Dependabot::Job, package_manager: "bundler", id: "123123", dependencies: [], dependency_groups: [])
  end

  describe "#handle_dependency_error" do
    let(:dependency) do
      instance_double(Dependabot::Dependency, name: "broken-biscuits")
    end

    let(:handle_dependency_error) do
      error_handler.handle_dependency_error(error: error, dependency: dependency)
    end

    context "with a handled known error" do
      let(:error) do
        Dependabot::DependencyFileNotResolvable.new("The file is full of bees")
      end

      it "records the error with the service and logs it out" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_resolvable",
          error_details: { message: "The file is full of bees" },
          dependency: dependency
        )

        expect(Dependabot.logger).to receive(:info).with(
          a_string_starting_with("Handled error whilst updating broken-biscuits:")
        )

        handle_dependency_error
      end
    end

    context "with a handled unknown error (cloud)" do
      let(:error) do
        StandardError.new("There are bees everywhere").tap do |err|
          err.set_backtrace ["bees.rb:5:in `buzz`"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the error with both update job error api services, logs the backtrace and captures the exception" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil,
          dependency: dependency
        )

        expect(mock_service).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => "bees.rb:5:in `buzz`",
            Dependabot::ErrorAttributes::MESSAGE => "There are bees everywhere",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCIES => [],
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        expect(mock_service).to receive(:capture_exception).with(
          error: error,
          job: mock_job,
          dependency: dependency,
          dependency_group: nil
        )

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing broken-biscuits (StandardError)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "There are bees everywhere"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "bees.rb:5:in `buzz`"
        )

        handle_dependency_error
      end
    end

    context "with a handled unknown error (ghes)" do
      let(:error) do
        StandardError.new("There are bees everywhere").tap do |err|
          err.set_backtrace ["bees.rb:5:in `buzz`"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, false)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records error with only update job error api service, logs the backtrace and captures the exception" do
        expect(mock_service).not_to receive(:record_update_job_unknown_error)

        expect(mock_service).to receive(:capture_exception).with(
          error: error,
          job: mock_job,
          dependency: dependency,
          dependency_group: nil
        )

        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil,
          dependency: dependency
        )

        handle_dependency_error
      end
    end

    context "with a job-halting error" do
      let(:error) do
        Dependabot::OutOfDisk.new("The disk is full of bees")
      end

      it "re-raises the error" do
        expect { handle_dependency_error }.to raise_error(error)
      end
    end

    context "with a NoChangeError surfaced from npm_and_yarn" do
      before do
        stub_const(
          "Dependabot::NpmAndYarn::FileUpdater::NoChangeError",
          Class.new(StandardError) do
            attr_reader :error_context

            def initialize(message:, error_context:)
              super(message)
              @error_context = error_context
            end
          end
        )
        allow(mock_job).to receive(:package_manager).and_return("npm_and_yarn")
      end

      let(:error_context_hash) do
        {
          reason: "files_unchanged",
          commands_succeeded: true,
          fallback_attempted: true,
          fallback_succeeded: false,
          package_manager: "npm",
          command_traces: [
            {
              package_manager: "npm",
              command: "install --package-lock-only",
              fingerprint: "install --package-lock-only",
              duration_ms: 12,
              success: true,
              content_changed_after: false
            },
            {
              package_manager: "npm",
              command: "audit fix",
              fingerprint: "audit fix",
              duration_ms: 7,
              success: true,
              content_changed_after: false
            }
          ]
        }
      end

      let(:error) do
        Dependabot::NpmAndYarn::FileUpdater::NoChangeError.new(
          message: "No files were updated", error_context: error_context_hash
        )
      end

      it "records a structured error and emits the updater.no_change metric" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "no_change_error",
          error_details: error_context_hash,
          dependency: dependency
        )

        expect(mock_service).to receive(:increment_metric).with(
          "updater.no_change",
          tags: {
            package_manager: "npm_and_yarn",
            reason: "files_unchanged",
            commands_succeeded: "true",
            fallback_attempted: "true",
            fallback_succeeded: "false"
          }
        )

        allow(Dependabot.logger).to receive(:info)
        allow(Dependabot.logger).to receive(:debug)

        handle_dependency_error

        expect(Dependabot.logger).to have_received(:info)
          .with(a_string_starting_with("Handled error whilst updating"))
        expect(Dependabot.logger).to have_received(:info)
          .with(a_string_starting_with("No-change diagnostics:"))
        # One info line per trace entry
        expect(Dependabot.logger).to have_received(:info)
          .with(a_string_matching(/trace\[0\].*install --package-lock-only/))
        expect(Dependabot.logger).to have_received(:info)
          .with(a_string_matching(/trace\[1\].*audit fix/))
      end
    end

    context "with a subprocess failure error (cloud)" do
      let(:error_context) do
        { bumblebees: "many", honeybees: "few", wasps: "none", fingerprint: "123456789" }
      end

      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "the kernal is full of bees",
          error_context: error_context
        ).tap do |err|
          err.set_backtrace ["****** ERROR 8335 -- 101"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the error with the service and logs the backtrace" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil,
          dependency: dependency
        )

        expect(mock_service).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => "****** ERROR 8335 -- 101",
            Dependabot::ErrorAttributes::MESSAGE => "the kernal is full of bees",
            Dependabot::ErrorAttributes::CLASS => "Dependabot::SharedHelpers::HelperSubprocessFailed",
            Dependabot::ErrorAttributes::FINGERPRINT => anything,
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCIES => [],
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        expect(mock_service).to receive(:capture_exception)

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing broken-biscuits (Dependabot::SharedHelpers::HelperSubprocessFailed)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "the kernal is full of bees"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "****** ERROR 8335 -- 101"
        )

        handle_dependency_error
      end

      it "sanitizes the error and captures it" do
        allow(Dependabot.logger).to receive(:error)
        allow(mock_service).to receive(:record_update_job_error)
        allow(mock_service).to receive(:record_update_job_unknown_error)
        expect(mock_service).to receive(:capture_exception).with(
          error: an_instance_of(Dependabot::Updater::SubprocessFailed), job: mock_job
        ) do |args|
          expect(args[:error].message)
            .to eq('Subprocess ["123456789"] failed to run. Check the job logs for error messages')
          expect(args[:error].sentry_context)
            .to eq(
              fingerprint: ["123456789"],
              extra: {
                bumblebees: "many", honeybees: "few", wasps: "none"
              }
            )
        end

        handle_dependency_error
      end
    end

    context "with a subprocess failure error (ghes)" do
      let(:error_context) do
        { bumblebees: "many", honeybees: "few", wasps: "none", fingerprint: "123456789" }
      end

      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "the kernal is full of bees",
          error_context: error_context
        ).tap do |err|
          err.set_backtrace ["****** ERROR 8335 -- 101"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, false)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the error with the service and logs the backtrace" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil,
          dependency: dependency
        )

        expect(mock_service).to receive(:capture_exception)

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing broken-biscuits (Dependabot::SharedHelpers::HelperSubprocessFailed)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "the kernal is full of bees"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "****** ERROR 8335 -- 101"
        )

        handle_dependency_error
      end

      it "sanitizes the error and captures it" do
        allow(Dependabot.logger).to receive(:error)
        allow(mock_service).to receive(:record_update_job_error)
        expect(mock_service).to receive(:capture_exception).with(
          error: an_instance_of(Dependabot::Updater::SubprocessFailed), job: mock_job
        ) do |args|
          expect(args[:error].message)
            .to eq('Subprocess ["123456789"] failed to run. Check the job logs for error messages')
          expect(args[:error].sentry_context)
            .to eq(
              fingerprint: ["123456789"],
              extra: {
                bumblebees: "many", honeybees: "few", wasps: "none"
              }
            )
        end

        handle_dependency_error
      end
    end

    context "with a nil dependency" do
      let(:dependency) { nil }

      let(:error) do
        StandardError.new("Something went wrong")
      end

      it "handles the nil dependency gracefully" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil,
          dependency: nil
        )

        expect(mock_service).to receive(:capture_exception).with(
          error: error,
          job: mock_job,
          dependency: nil,
          dependency_group: nil
        )

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing unknown dependency (StandardError)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "Something went wrong"
        )

        handle_dependency_error
      end
    end
  end

  describe "handle_job_error" do
    let(:handle_job_error) do
      error_handler.handle_job_error(error: error)
    end

    context "with a handled known error" do
      let(:error) do
        Dependabot::DependencyFileNotResolvable.new("The file is full of bees")
      end

      it "records the error with the service and logs it out" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_resolvable",
          error_details: { message: "The file is full of bees" }
        )

        expect(Dependabot.logger).to receive(:info).with(
          a_string_starting_with("Handled error whilst processing job:")
        )

        handle_job_error
      end
    end

    context "with a handled unknown error (cloud)" do
      let(:error) do
        StandardError.new("There are bees everywhere").tap do |err|
          err.set_backtrace ["bees.rb:5:in `buzz`"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the error with the update job error services, logs the backtrace and captures the exception" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil
        )

        expect(mock_service).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => "bees.rb:5:in `buzz`",
            Dependabot::ErrorAttributes::MESSAGE => "There are bees everywhere",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCIES => [],
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        expect(mock_service).to receive(:capture_exception).with(
          error: error,
          job: mock_job,
          dependency: nil,
          dependency_group: nil
        )

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing job (StandardError)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "There are bees everywhere"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "bees.rb:5:in `buzz`"
        )

        handle_job_error
      end
    end

    context "with a handled unknown error (ghes)" do
      let(:error) do
        StandardError.new("There are bees everywhere").tap do |err|
          err.set_backtrace ["bees.rb:5:in `buzz`"]
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, false)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the error with the update job error services, logs the backtrace and captures the exception" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil
        )

        expect(mock_service).to receive(:capture_exception).with(
          error: error,
          job: mock_job,
          dependency: nil,
          dependency_group: nil
        )

        expect(Dependabot.logger).to receive(:error).with(
          "Error processing job (StandardError)"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "There are bees everywhere"
        )
        expect(Dependabot.logger).to receive(:error).with(
          "bees.rb:5:in `buzz`"
        )

        handle_job_error
      end
    end

    context "with a job-halting error" do
      let(:error) do
        Dependabot::OutOfDisk.new("The disk is full of bees")
      end

      it "re-raises the error" do
        expect { handle_job_error }.to raise_error(error)
      end
    end
  end
end
