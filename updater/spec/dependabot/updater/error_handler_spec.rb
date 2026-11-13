# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/errors"
require "dependabot/job"
require "dependabot/registry_client"
require "dependabot/service"
require "dependabot/shared_helpers"
require "dependabot/updater/error_handler"

RSpec.describe Dependabot::Updater::ErrorHandler do
  subject(:error_handler) do
    described_class.new(
      service: mock_service,
      job: mock_job,
      operation_name: operation_name
    )
  end

  let(:operation_name) { "update_all_versions" }

  let(:mock_service) do
    instance_double(Dependabot::Service).tap do |service|
      allow(service).to receive(:increment_metric)
    end
  end

  let(:mock_job) do
    instance_double(
      Dependabot::Job,
      package_manager: "bundler",
      id: "123123",
      dependencies: [],
      dependency_groups: [],
      self_hosted_runner?: self_hosted_runner
    )
  end

  let(:self_hosted_runner) { false }

  describe "#handle_dependency_error" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "broken-biscuits",
        version: "1.2.0",
        previous_version: "1.1.0",
        package_manager: "bundler",
        requirements: [{ file: "Gemfile", requirement: "~> 1.2", groups: [], source: nil }]
      )
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

    context "when a blocked version is enforced" do
      let(:error) do
        Dependabot::BlockedDependencyVersion.new(
          dependency_name: "transitive-dep",
          blocked_version: "1.5.0",
          version_requirement: "= 1.5.0",
          reason: "malware"
        )
      end

      # operation_name is the canonical "update_all_versions" tag; the metric maps
      # it onto the curated "version_update" label shared with blocked_versions.ignored.
      it "increments blocked_versions.enforced metric with operation and package manager" do
        expect(mock_service).to receive(:increment_metric).with(
          "blocked_versions.enforced",
          tags: { operation: "version_update", package_manager: "bundler" }
        )

        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "blocked_dependency_version",
          error_details: {
            "dependency-name": "transitive-dep",
            "blocked-version": "1.5.0",
            "version-requirement": "= 1.5.0",
            reason: "malware"
          },
          dependency: dependency
        )

        handle_dependency_error
      end

      context "when the operation has no curated label" do
        let(:operation_name) { "some_future_operation" }

        it "falls back to the raw operation name" do
          expect(mock_service).to receive(:increment_metric).with(
            "blocked_versions.enforced",
            tags: { operation: "some_future_operation", package_manager: "bundler" }
          )

          allow(mock_service).to receive(:record_update_job_error)

          handle_dependency_error
        end
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
            Dependabot::ErrorAttributes::CONTEXT => {
              "dependency-name" => "broken-biscuits",
              "dependency-version" => "1.2.0",
              "dependency-previous-version" => "1.1.0",
              "dependency-requirement-files" => ["Gemfile"]
            },
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

    context "with an EOF socket error (cloud)" do
      let(:error) do
        Excon::Error::Socket.new(EOFError.new).tap do |socket_error|
          socket_error.set_backtrace(
            [
              "/home/dependabot/common/lib/dependabot/registry_client.rb:32:in 'get'",
              "/home/dependabot/bundler/lib/dependabot/bundler/package/package_details_fetcher.rb:100:" \
              "in 'package_json_response'"
            ]
          )
        end
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
        allow(mock_service).to receive(:capture_exception)
        allow(mock_service).to receive(:record_update_job_error)
        allow(Dependabot.logger).to receive(:error)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "records the unknown error without a fingerprint" do
        expect(mock_service).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_error",
          error_details: hash_excluding(
            Dependabot::ErrorAttributes::FINGERPRINT
          )
        )

        handle_dependency_error
      end
    end

    # On a self-hosted runner the job runs in the customer's network. When that network blocks or cannot resolve a
    # registry, the Dependabot proxy closes the connection without a response (EOFError) or the request times out.
    context "when a registry can't be reached from a self-hosted runner" do
      let(:self_hosted_runner) { true }
      let(:url) { "https://pypi.org/pypi/requests/json" }
      let(:raised) { Excon::Error::Socket.new(EOFError.new("end of file reached")) }

      # Raised through RegistryClient, which records the registry's host on the error
      let(:error) do
        stub_request(:get, url).to_raise(raised)
        Dependabot::RegistryClient.get(url: url)
      rescue StandardError => e
        e
      end

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
        allow(Dependabot.logger).to receive(:info)
        allow(Dependabot.logger).to receive(:warn)
      end

      after do
        Dependabot::Experiments.reset!
        Dependabot::RegistryClient.clear_cache!
      end

      it "records registry_unreachable with the registry's host, and not as an unknown error" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "registry_unreachable",
          error_details: { source: "pypi.org" },
          dependency: dependency
        )
        expect(mock_service).not_to receive(:record_update_job_unknown_error)
        expect(mock_service).not_to receive(:capture_exception)

        handle_dependency_error

        expect(Dependabot.logger).to have_received(:info).with(
          a_string_starting_with("Handled error whilst updating broken-biscuits: registry_unreachable")
        )
      end

      it "says in the log what to check" do
        allow(mock_service).to receive(:record_update_job_error)

        handle_dependency_error

        expect(Dependabot.logger).to have_received(:warn).with(
          a_string_including("pypi.org", "self-hosted runner", "EOFError")
        )
      end

      context "when the request times out" do
        let(:raised) { Excon::Error::Timeout.new("read timeout reached") }

        it "records registry_unreachable" do
          expect(mock_service).to receive(:record_update_job_error).with(
            error_type: "registry_unreachable",
            error_details: { source: "pypi.org" },
            dependency: dependency
          )

          handle_dependency_error
        end
      end

      # A request that does not go through RegistryClient has no recorded host. Fetching a Git repository's refs is one
      # (GitMetadataFetcher re-raises socket errors and timeouts for known Git hosts), and an unreachable Git host is
      # not an unreachable package registry
      context "when the request did not go through RegistryClient, such as a Git host that times out" do
        let(:error) { Excon::Error::Timeout.new("read timeout reached") }

        it "records an unknown error as before, and still captures the exception" do
          allow(Dependabot.logger).to receive(:error)
          expect(mock_service).to receive(:capture_exception)
          expect(mock_service).to receive(:record_update_job_unknown_error)
          expect(mock_service).to receive(:record_update_job_error).with(
            error_type: "unknown_error",
            error_details: nil,
            dependency: dependency
          )

          handle_dependency_error
        end

        context "with a closed connection" do
          let(:error) { Excon::Error::Socket.new(EOFError.new("end of file reached")) }

          it "records an unknown error as before" do
            allow(Dependabot.logger).to receive(:error)
            expect(mock_service).to receive(:capture_exception)
            expect(mock_service).to receive(:record_update_job_unknown_error)
            expect(mock_service).to receive(:record_update_job_error).with(
              error_type: "unknown_error",
              error_details: nil,
              dependency: dependency
            )

            handle_dependency_error
          end
        end
      end

      # Excon::Error::Certificate is an Excon::Error::Socket, but a certificate that can't be verified means a server
      # answered: the network path works, and the problem is certificate trust
      context "when the registry's certificate can't be verified" do
        let(:raised) { Excon::Error::Certificate.new(OpenSSL::SSL::SSLError.new("certificate verify failed")) }

        it "records an unknown error as before" do
          allow(Dependabot.logger).to receive(:error)
          expect(mock_service).to receive(:capture_exception)
          expect(mock_service).to receive(:record_update_job_unknown_error)
          expect(mock_service).to receive(:record_update_job_error).with(
            error_type: "unknown_error",
            error_details: nil,
            dependency: dependency
          )

          handle_dependency_error
        end
      end

      context "when the ecosystem already classified the error" do
        let(:error) { Dependabot::PrivateSourceTimedOut.new("https://registry.example.com") }

        it "keeps the ecosystem's error type" do
          expect(mock_service).to receive(:record_update_job_error).with(
            error_type: "private_source_timed_out",
            error_details: { source: "https://registry.example.com" },
            dependency: dependency
          )

          handle_dependency_error
        end
      end

      # GitHub-hosted runners, and versions of dependabot-api (including older GHES releases) that don't say where the
      # job runs, keep reporting an unknown error
      context "when the job doesn't run on a self-hosted runner" do
        let(:self_hosted_runner) { false }

        it "records an unknown error as before" do
          allow(Dependabot.logger).to receive(:error)
          expect(mock_service).to receive(:capture_exception)
          expect(mock_service).to receive(:record_update_job_unknown_error)
          expect(mock_service).to receive(:record_update_job_error).with(
            error_type: "unknown_error",
            error_details: nil,
            dependency: dependency
          )

          handle_dependency_error
        end
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
            Dependabot::ErrorAttributes::FINGERPRINT => ["123456789"],
            Dependabot::ErrorAttributes::CONTEXT => {
              "dependency-name" => "broken-biscuits",
              "dependency-version" => "1.2.0",
              "dependency-previous-version" => "1.1.0",
              "dependency-requirement-files" => ["Gemfile"],
              "helper-error-class" => "HelperSubprocessFailed"
            },
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
          expect(Dependabot::ErrorReportContext.build(error: args[:error]))
            .to eq(
              "dependency-name" => "broken-biscuits",
              "dependency-version" => "1.2.0",
              "dependency-previous-version" => "1.1.0",
              "dependency-requirement-files" => ["Gemfile"],
              "helper-error-class" => "HelperSubprocessFailed"
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

    context "when a registry can't be reached from a self-hosted runner" do
      let(:self_hosted_runner) { true }
      let(:url) { "https://repo.maven.apache.org/maven2/org/example/lib/maven-metadata.xml" }

      let(:error) do
        stub_request(:get, url).to_raise(Excon::Error::Socket.new(EOFError.new("end of file reached")))
        Dependabot::RegistryClient.get(url: url)
      rescue StandardError => e
        e
      end

      before { allow(Dependabot.logger).to receive(:warn) }

      after { Dependabot::RegistryClient.clear_cache! }

      it "records registry_unreachable with the registry's host" do
        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "registry_unreachable",
          error_details: { source: "repo.maven.apache.org" }
        )
        expect(mock_service).not_to receive(:capture_exception)
        expect(Dependabot.logger).to receive(:info).with(
          a_string_starting_with("Handled error whilst processing job: registry_unreachable")
        )

        handle_job_error
      end
    end

    context "when a blocked version is enforced" do
      let(:error) do
        Dependabot::BlockedDependencyVersion.new(
          dependency_name: "transitive-dep",
          blocked_version: "1.5.0",
          version_requirement: "= 1.5.0"
        )
      end

      it "increments blocked_versions.enforced metric with operation and package manager" do
        expect(mock_service).to receive(:increment_metric).with(
          "blocked_versions.enforced",
          tags: { operation: "version_update", package_manager: "bundler" }
        )

        expect(mock_service).to receive(:record_update_job_error).with(
          error_type: "blocked_dependency_version",
          error_details: {
            "dependency-name": "transitive-dep",
            "blocked-version": "1.5.0",
            "version-requirement": "= 1.5.0"
          }
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
