# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_files_command"
require "tmpdir"

RSpec.describe Dependabot::UpdateFilesCommand do
  subject(:job) { described_class.new }

  let(:service) do
    instance_double(Dependabot::Service, mark_job_as_processed: nil)
  end
  let(:job_definition) do
    JSON.parse(fixture("file_fetcher_output/output.json"))
  end
  let(:repo_contents_path) { "repo/path" }
  let(:job_id) { "123123" }

  before do
    allow(Dependabot::Service).to receive(:new).and_return(service)
    allow(Dependabot::Environment).to receive(:job_id).and_return(job_id)
    allow(Dependabot::Environment).to receive(:job_token).and_return("mock_token")
    allow(Dependabot::Environment).to receive(:job_definition).and_return(job_definition)
    allow(Dependabot::Environment).to receive(:repo_contents_path).and_return(repo_contents_path)
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
          dependency_files: anything,
          base_commit_sha: base_commit_sha
        ).
        and_return(dummy_runner)
      expect(dummy_runner).to receive(:run)
      expect(service).to receive(:mark_job_as_processed).
        with(base_commit_sha)

      perform_job
    end

    context "with vendoring_dependencies" do
      let(:job_definition) do
        JSON.parse(fixture("file_fetcher_output/vendoring_output.json"))
      end

      it "delegates to Dependabot::Updater" do
        dummy_runner = double(run: nil)
        base_commit_sha = "1c6331732c41e4557a16dacb82534f1d1c831848"
        expect(Dependabot::Updater).
          to receive(:new).
          with(
            service: service,
            job: an_object_having_attributes(id: job_id, repo_contents_path: repo_contents_path),
            dependency_files: anything,
            base_commit_sha: base_commit_sha
          ).
          and_return(dummy_runner)
        expect(dummy_runner).to receive(:run)
        expect(service).to receive(:mark_job_as_processed).
          with(base_commit_sha)

        perform_job
      end
    end
  end
end
