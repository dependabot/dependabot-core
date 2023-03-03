# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_files_command"
require "tmpdir"

RSpec.describe Dependabot::UpdateFilesCommand do
  subject(:job) { described_class.new }

  let(:service) { double(Dependabot::Service) }
  let(:job_definition) do
    JSON.parse(fixture("file_fetcher_output/output.json"))
  end
  let(:repo_contents_path) { "repo/path" }
  let(:job_id) { "123123" }

  before do
    allow(job).to receive(:service).and_return(service)
    allow(job).to receive(:job_id).and_return(job_id)
    allow(service).to receive(:mark_job_as_processed)

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
          job_id: job_id,
          job: anything,
          dependency_files: anything,
          repo_contents_path: nil,
          base_commit_sha: base_commit_sha
        ).
        and_return(dummy_runner)
      expect(dummy_runner).to receive(:run)
      expect(service).to receive(:mark_job_as_processed).
        with(job_id, base_commit_sha)

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
            job_id: job_id,
            job: anything,
            dependency_files: anything,
            repo_contents_path: repo_contents_path,
            base_commit_sha: base_commit_sha
          ).
          and_return(dummy_runner)
        expect(dummy_runner).to receive(:run)
        expect(service).to receive(:mark_job_as_processed).
          with(job_id, base_commit_sha)

        perform_job
      end
    end
  end
end
