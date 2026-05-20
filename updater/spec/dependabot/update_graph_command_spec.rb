# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_graph_command"
require "dependabot/bundler"
require "tmpdir"

RSpec.describe Dependabot::UpdateGraphCommand do
  subject(:job) { described_class.new(fetched_files) }

  let(:service) do
    instance_double(
      Dependabot::Service,
      capture_exception: nil,
      mark_job_as_processed: nil,
      record_update_job_error: nil,
      record_update_job_unknown_error: nil,
      update_dependency_list: nil,
      increment_metric: nil,
      wait_for_calls_to_finish: nil
    )
  end
  let(:job_definition) do
    JSON.parse(fixture("jobs/bundler_directories.json"))
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("bundler/original/Gemfile"),
      directory: "/"
    )
  end
  let(:fetched_files) do
    # We no longer write encoded files to disk, need to migrate the fixtures in this test
    Dependabot::FetchedFiles.new(
      dependency_files: [manifest],
      base_commit_sha: "1c6331732c41e4557a16dacb82534f1d1c831848"
    )
  end
  let(:job_id) { "123123" }

  before do
    allow(Dependabot::Service).to receive(:new).and_return(service)
    allow(Dependabot::Environment).to receive_messages(
      job_id: job_id,
      job_token: "mock_token",
      job_definition: job_definition,
      repo_contents_path: nil
    )
  end

  describe "#perform_job" do
    subject(:perform_job) { job.perform_job }

    it "emits a create_dependency_submission call to the Dependabot service" do
      expect(service).to receive(:create_dependency_submission) do |args|
        expect(args[:dependency_submission]).to be_a(GithubApi::DependencySubmission)

        expect(args[:dependency_submission].job_id).to eql(job_id)
        expect(args[:dependency_submission].package_manager).to eql("bundler")
      end

      perform_job
    end
  end

  describe "#perform_job when the directory is empty or doesn't exist" do
    subject(:perform_job) { job.perform_job }

    let(:fetched_files) do
      Dependabot::FetchedFiles.new(
        dependency_files: [],
        base_commit_sha: "1c6331732c41e4557a16dacb82534f1d1c831848"
      )
    end

    before do
      allow(Dependabot::FileParsers).to receive(:for_package_manager)
      allow(Dependabot::DependencyGraphers).to receive(:for_package_manager)
    end

    it "emits a create_dependency_submission call to the Dependabot service with an empty snapshot" do
      expect(service).to receive(:create_dependency_submission) do |args|
        expected_manifest_file = Dependabot::DependencyFile.new(name: "", content: "", directory: "/")

        expect(args[:dependency_submission]).to be_a(GithubApi::DependencySubmission)

        expect(args[:dependency_submission].job_id).to eql(job_id)
        expect(args[:dependency_submission].package_manager).to eql("bundler")
        expect(args[:dependency_submission].resolved_dependencies).to be_empty
        expect(args[:dependency_submission].manifest_file).to eql(expected_manifest_file)

        # parsers and graphers should not be invoked
        expect(Dependabot::FileParsers).not_to have_received(:for_package_manager)
        expect(Dependabot::DependencyGraphers).not_to have_received(:for_package_manager)
      end

      perform_job
    end
  end

  describe "#perform_job when there is an error parsing the dependency files" do
    subject(:perform_job) { job.perform_job }

    before do
      allow(Dependabot.logger).to receive(:info)
      allow(Dependabot.logger).to receive(:error)
      allow(Sentry).to receive(:capture_exception)

      mock_processor = instance_double(Dependabot::UpdateGraphProcessor)
      allow(mock_processor).to receive(:run).and_raise(error)
      allow(Dependabot::UpdateGraphProcessor).to receive(:new).and_return(mock_processor)
    end

    shared_examples "a fast-failed job" do
      it "marks the job as processed" do
        expect(service).to receive(:mark_job_as_processed)

        perform_job
      end
    end

    context "with an update graph error (cloud)" do
      let(:error) { StandardError.new("hell") }

      before do
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it_behaves_like "a fast-failed job"

      it "captures the exception and records to a update job error api" do
        expect(service).to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "unknown_update_graph_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "hell",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        perform_job
      end

      it "captures the exception and records the a update job unknown error api" do
        expect(service).to receive(:capture_exception)
        expect(service).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_update_graph_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "hell",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        perform_job
        Dependabot::Experiments.reset!
      end
    end

    context "with an update graph error (ghes)" do
      let(:error) { StandardError.new("hell") }

      it_behaves_like "a fast-failed job"

      it "captures the exception and records to a update job error api" do
        expect(service).to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "unknown_update_graph_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "hell",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )

        perform_job
      end

      it "captures the exception and does not records the update job unknown error api" do
        expect(service).to receive(:capture_exception)
        expect(service).not_to receive(:record_update_job_unknown_error)

        perform_job
        Dependabot::Experiments.reset!
      end
    end

    context "with a Dependabot::RepoNotFound error" do
      let(:error) { Dependabot::RepoNotFound.new("dependabot/four-oh-four") }

      it_behaves_like "a fast-failed job"

      it "does not capture the exception or record a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).not_to receive(:record_update_job_error)

        perform_job
      end
    end

    Dependabot::Updater::ErrorHandler::RUN_HALTING_ERRORS.each do |error_class, error_type|
      context "with #{error_class}" do
        let(:error) do
          if error_class == Octokit::Unauthorized
            Octokit::Unauthorized.new
          else
            error_class.new("message")
          end
        end

        it_behaves_like "a fast-failed job"

        it "only records a job error" do
          expect(service).not_to receive(:capture_exception)
          expect(service).to receive(:record_update_job_error).with(
            error_type: error_type,
            error_details: nil
          )

          perform_job
        end
      end
    end
  end
end
