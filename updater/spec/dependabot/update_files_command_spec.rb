# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_files_command"
require "tmpdir"

RSpec.describe Dependabot::UpdateFilesCommand do
  subject(:job) { described_class.new }

  let(:service) do
    instance_double(Dependabot::Service,
                    capture_exception: nil,
                    mark_job_as_processed: nil,
                    record_update_job_error: nil,
                    update_dependency_list: nil,
                    increment_metric: nil)
  end
  let(:job_definition) do
    JSON.parse(fixture("file_fetcher_output/output.json"))
  end
  let(:job_id) { "123123" }

  before do
    allow(Dependabot::Service).to receive(:new).and_return(service)
    allow(Dependabot::Environment).to receive(:job_id).and_return(job_id)
    allow(Dependabot::Environment).to receive(:job_token).and_return("mock_token")
    allow(Dependabot::Environment).to receive(:job_definition).and_return(job_definition)
    allow(Dependabot::Environment).to receive(:repo_contents_path).and_return(nil)
  end

  describe "#perform_job" do
    subject(:perform_job) { job.perform_job }

    it "delegates to Dependabot::Updater" do
      dummy_runner = double(run: nil)
      base_commit_sha = "1c6331732c41e4557a16dacb82534f1d1c831848"
      expect(Dependabot::Updater).
        to receive(:new).
        with(
          service: service,
          job: an_object_having_attributes(id: job_id, repo_contents_path: nil),
          dependency_snapshot: an_object_having_attributes(base_commit_sha: base_commit_sha)
        ).
        and_return(dummy_runner)
      expect(dummy_runner).to receive(:run)
      expect(service).to receive(:mark_job_as_processed).
        with(base_commit_sha)

      perform_job
    end

    it "sends dependency metadata to the service" do
      expect(service).to receive(:update_dependency_list).
        with(dependency_snapshot: an_instance_of(Dependabot::DependencySnapshot))

      perform_job
    end

    context "with vendoring_dependencies" do
      let(:snapshot) do
        instance_double(Dependabot::DependencySnapshot,
                        base_commit_sha: "1c6331732c41e4557a16dacb82534f1d1c831848")
      end
      let(:repo_contents_path) { "repo/path" }

      let(:job_definition) do
        JSON.parse(fixture("file_fetcher_output/vendoring_output.json"))
      end

      before do
        allow(Dependabot::Environment).to receive(:repo_contents_path).and_return(repo_contents_path)
        allow(Dependabot::DependencySnapshot).to receive(:create_from_job_definition).and_return(snapshot)
      end

      it "delegates to Dependabot::Updater" do
        dummy_runner = double(run: nil)
        base_commit_sha = "1c6331732c41e4557a16dacb82534f1d1c831848"
        expect(Dependabot::Updater).
          to receive(:new).
          with(
            service: service,
            job: an_object_having_attributes(id: job_id, repo_contents_path: repo_contents_path),
            dependency_snapshot: snapshot
          ).
          and_return(dummy_runner)
        expect(dummy_runner).to receive(:run)
        expect(service).to receive(:mark_job_as_processed).
          with(base_commit_sha)

        perform_job
      end
    end
  end

  describe "#perform_job when there is an error parsing the dependency files" do
    subject(:perform_job) { job.perform_job }

    before do
      allow(Dependabot.logger).to receive(:info)
      allow(Dependabot.logger).to receive(:error)
      allow(Raven).to receive(:capture_exception)
      allow(Dependabot::DependencySnapshot).to receive(:create_from_job_definition).and_raise(error)
    end

    shared_examples "a fast-failed job" do
      it "marks the job as processed without proceeding further" do
        expect(service).to receive(:mark_job_as_processed)
        expect(Dependabot::Updater).not_to receive(:new)

        perform_job
      end
    end

    context "with an unknown error" do
      let(:error) { StandardError.new("hell") }

      it_behaves_like "a fast-failed job"

      it "it captures the exception and records the a job error" do
        expect(service).to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil
        )

        perform_job
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

    context "with a Dependabot::DependencyFileNotEvaluatable error" do
      let(:error) { Dependabot::DependencyFileNotEvaluatable.new("message") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_evaluatable",
          error_details: { message: "message" }
        )

        perform_job
      end
    end

    context "with a Dependabot::DependencyFileNotResolvable error" do
      let(:error) { Dependabot::DependencyFileNotResolvable.new("message") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_resolvable",
          error_details: { message: "message" }
        )

        perform_job
      end
    end

    context "with a Dependabot::BranchNotFound error" do
      let(:error) { Dependabot::BranchNotFound.new("my_branch") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "branch_not_found",
          error_details: { "branch-name": "my_branch" }
        )

        perform_job
      end
    end

    context "with a Dependabot::DependencyFileNotParseable error" do
      let(:error) { Dependabot::DependencyFileNotParseable.new("path/to/file", "a") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_parseable",
          error_details: { "file-path": "path/to/file", message: "a" }
        )

        perform_job
      end
    end

    context "with a Dependabot::DependencyFileNotFound error" do
      let(:error) { Dependabot::DependencyFileNotFound.new("path/to/file") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "dependency_file_not_found",
          error_details: { "file-path": "path/to/file" }
        )

        perform_job
      end
    end

    context "with a Dependabot::PathDependenciesNotReachable error" do
      let(:error) { Dependabot::PathDependenciesNotReachable.new(["bad_gem"]) }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "path_dependencies_not_reachable",
          error_details: { dependencies: ["bad_gem"] }
        )

        perform_job
      end
    end

    context "with a Dependabot::PrivateSourceAuthenticationFailure error" do
      let(:error) { Dependabot::PrivateSourceAuthenticationFailure.new("some.example.com") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "private_source_authentication_failure",
          error_details: { source: "some.example.com" }
        )

        perform_job
      end
    end

    context "with a Dependabot::GitDependenciesNotReachable error" do
      let(:error) { Dependabot::GitDependenciesNotReachable.new("https://example.com") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "git_dependencies_not_reachable",
          error_details: { "dependency-urls": ["https://example.com"] }
        )

        perform_job
      end
    end

    context "with a Dependabot::NotImplemented error" do
      let(:error) { Dependabot::NotImplemented.new("foo") }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "not_implemented",
          error_details: { message: "foo" }
        )

        perform_job
      end
    end

    context "with Octokit::ServerError" do
      let(:error) { Octokit::ServerError.new }

      it_behaves_like "a fast-failed job"

      it "only records a job error" do
        expect(service).not_to receive(:capture_exception)
        expect(service).to receive(:record_update_job_error).with(
          error_type: "unknown_error",
          error_details: nil
        )

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
