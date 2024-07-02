# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_fetcher_command"
require "dependabot/errors"
require "tmpdir"

require "support/dummy_package_manager/dummy"

require "dependabot/bundler"

RSpec.describe Dependabot::FileFetcherCommand do
  subject(:job) { described_class.new }

  let(:api_client) { double(Dependabot::ApiClient) }
  let(:job_id) { "123123" }

  before do
    allow(Dependabot::ApiClient).to receive(:new).and_return(api_client)

    allow(api_client).to receive(:mark_job_as_processed)
    allow(api_client).to receive(:record_update_job_error)
    allow(api_client).to receive(:record_ecosystem_versions)
    allow(api_client).to receive(:is_a?).with(Dependabot::ApiClient).and_return(true)

    allow(Dependabot::Environment).to receive_messages(job_id: job_id, job_token: "job_token",
                                                       output_path: File.join(Dir.mktmpdir,
                                                                              "output.json"),
                                                       job_definition: job_definition,
                                                       job_path: nil)
  end

  describe "#perform_job" do
    subject(:perform_job) { job.perform_job }

    let(:job_definition) do
      JSON.parse(fixture("jobs/job_with_credentials.json"))
    end

    after do
      # The job definition in this context loads an experiment, so reset it
      Dependabot::Experiments.reset!
    end

    it "fetches the files and writes the fetched files to output.json", :vcr do
      expect(api_client).not_to receive(:mark_job_as_processed)

      perform_job

      output = JSON.parse(File.read(Dependabot::Environment.output_path))
      dependency_file = output["base64_dependency_files"][0]
      expect(dependency_file["name"]).to eq(
        "dependabot-test-ruby-package.gemspec"
      )
      expect(dependency_file["content_encoding"]).to eq("utf-8")
    end

    context "when the fetcher raises a ToolVersionNotSupported error", :vcr do
      before do
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit).and_return("a" * 40)
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:files).and_return([])
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:ecosystem_versions)
          .and_raise(Dependabot::ToolVersionNotSupported.new("Bundler", "1.7", "2.x"))
      end

      it "tells the backend about the error (and doesn't re-raise it)" do
        expect(api_client)
          .to receive(:record_update_job_error)
          .with(
            error_details: { "tool-name": "Bundler", "detected-version": "1.7", "supported-versions": "2.x" },
            error_type: "tool_version_not_supported"
          )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end
    end

    context "when the fetcher raises a BranchNotFound error" do
      before do
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit)
          .and_raise(Dependabot::BranchNotFound, "my_branch")
      end

      it "tells the backend about the error (and doesn't re-raise it)" do
        expect(api_client)
          .to receive(:record_update_job_error)
          .with(
            error_details: { "branch-name": "my_branch" },
            error_type: "branch_not_found"
          )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end
    end

    context "when the fetcher raises a RepoNotFound error" do
      let(:provider) { job_definition.dig("job", "source", "provider") }
      let(:repo) { job_definition.dig("job", "source", "repo") }
      let(:source) { ::Dependabot::Source.new(provider: provider, repo: repo) }

      before do
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit)
          .and_raise(Dependabot::RepoNotFound, source)
      end

      it "tells the backend about the error (and doesn't re-raise it)" do
        expect(api_client)
          .to receive(:record_update_job_error)
          .with(
            error_details: { message: "Dependabot::RepoNotFound" },
            error_type: "job_repo_not_found"
          )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end
    end

    context "when the fetcher raises a file fetcher error (cloud)", :vcr do
      before do
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit)
          .and_raise(StandardError, "my_branch")
        Dependabot::Experiments.register(:record_update_job_unknown_error, true)
      end

      after do
        Dependabot::Experiments.reset!
      end

      it "tells the backend about the error via update job error api (and doesn't re-raise it)" do
        expect(api_client).to receive(:record_update_job_error).with(
          error_type: "file_fetcher_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "my_branch",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )
        expect(api_client).to receive(:record_update_job_unknown_error)
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end

      it "tells the backend about the error via update job unknown error (and doesn't re-raise it)" do
        expect(api_client).to receive(:record_update_job_unknown_error).with(
          error_type: "unknown_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "my_branch",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => [],
            Dependabot::ErrorAttributes::SECURITY_UPDATE => "false"
          }
        )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end
    end

    context "when the fetcher raises a file fetcher error (ghes)", :vcr do
      before do
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit)
          .and_raise(StandardError, "my_branch")
      end

      it "tells the backend about the error via update job error api (and doesn't re-raise it)" do
        expect(api_client).to receive(:record_update_job_error).with(
          error_type: "file_fetcher_error",
          error_details: {
            Dependabot::ErrorAttributes::BACKTRACE => an_instance_of(String),
            Dependabot::ErrorAttributes::MESSAGE => "my_branch",
            Dependabot::ErrorAttributes::CLASS => "StandardError",
            Dependabot::ErrorAttributes::PACKAGE_MANAGER => "bundler",
            Dependabot::ErrorAttributes::JOB_ID => "123123",
            Dependabot::ErrorAttributes::DEPENDENCY_GROUPS => []
          }
        )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end

      it "do not tells the backend about the error" do
        expect(api_client).not_to receive(:record_update_job_unknown_error)
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
      end
    end

    context "when the fetcher raises a rate limited error" do
      let(:reset_at) { Time.now + 30 }

      before do
        exception = Octokit::TooManyRequests.new(
          response_headers: {
            "X-RateLimit-Reset" => reset_at
          }
        )
        allow_any_instance_of(Dependabot::Bundler::FileFetcher)
          .to receive(:commit)
          .and_raise(exception)
      end

      it "retries the job when the rate-limit is reset and reports api error" do
        expect(Sentry).not_to receive(:capture_exception)
        expect(api_client)
          .to receive(:record_update_job_error)
          .with(
            error_details: { "rate-limit-reset": reset_at },
            error_type: "octokit_rate_limited"
          )
        expect(api_client).to receive(:mark_job_as_processed)

        expect { perform_job }.to output(/Repository is rate limited, attempting to retry/).to_stdout_from_any_process
      end
    end

    context "when vendoring dependencies", :vcr do
      let(:job_definition) do
        JSON.parse(fixture("jobs/job_with_vendor_dependencies.json"))
      end

      before do
        allow(Dependabot::Environment).to receive(:repo_contents_path).and_return(Dir.mktmpdir)
      end

      it "clones the repo" do
        expect(api_client).not_to receive(:mark_job_as_processed)

        perform_job

        root_dir_entries = Dir.entries(Dependabot::Environment.repo_contents_path)
        expect(root_dir_entries).to include(".gitignore")
        expect(root_dir_entries).to include(
          "dependabot-test-ruby-package.gemspec"
        )
        expect(root_dir_entries).to include("README.md")
      end
    end

    context "when package ecosystem always clones" do
      let(:job_definition) do
        JSON.parse(fixture("jobs/job_with_dummy.json"))
      end

      before do
        allow(Dependabot::Environment).to receive(:repo_contents_path).and_return(Dir.mktmpdir)
      end

      it "clones the repo" do
        perform_job

        root_dir_entries = Dir.entries(Dependabot::Environment.repo_contents_path)
        expect(root_dir_entries).to include("go.mod")
        expect(root_dir_entries).to include("go.sum")
        expect(root_dir_entries).to include("main.go")
      end

      context "when the fetcher raises a BranchNotFound error while cloning" do
        before do
          allow_any_instance_of(DummyPackageManager::FileFetcher)
            .to receive(:clone_repo_contents)
            .and_raise(Dependabot::BranchNotFound, "my_branch")
        end

        it "tells the backend about the error (and doesn't re-raise it)" do
          expect(api_client)
            .to receive(:record_update_job_error)
            .with(
              error_details: { "branch-name": "my_branch" },
              error_type: "branch_not_found"
            )
          expect(api_client).to receive(:mark_job_as_processed)

          expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
        end
      end

      context "when the fetcher raises a OutOfDisk error while cloning" do
        before do
          allow_any_instance_of(DummyPackageManager::FileFetcher)
            .to receive(:clone_repo_contents)
            .and_raise(Dependabot::OutOfDisk)
        end

        it "tells the backend about the error (and doesn't re-raise it)" do
          expect(api_client)
            .to receive(:record_update_job_error)
            .with(
              error_details: {},
              error_type: "out_of_disk"
            )
          expect(api_client).to receive(:mark_job_as_processed)

          expect { perform_job }.to output(/Error during file fetching; aborting/).to_stdout_from_any_process
        end
      end
    end

    context "when the connectivity check is enabled", :vcr do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ENABLE_CONNECTIVITY_CHECK").and_return("1")
      end

      it "logs connectivity is successful and does not raise an error" do
        allow(Dependabot.logger).to receive(:info)

        expect { perform_job }.not_to raise_error

        expect(Dependabot.logger).to have_received(:info).with(/Connectivity check starting/)
        expect(Dependabot.logger).to have_received(:info).with(/Connectivity check successful/)
      end

      context "when connectivity is broken" do
        let(:mock_octokit) { instance_double(Octokit::Client) }

        before do
          allow(Octokit::Client)
            .to receive(:new)
            .and_call_original
          allow(Octokit::Client)
            .to receive(:new).with({
              api_endpoint: "https://api.github.com/",
              connection_options: {
                request: {
                  open_timeout: 20,
                  timeout: 5
                }
              }
            })
                             .and_return(mock_octokit)
          allow(mock_octokit).to receive(:repository)
            .and_raise(Octokit::Error)
        end

        it "logs connectivity failed and does not raise an error" do
          allow(Dependabot.logger).to receive(:info)
          allow(Dependabot.logger).to receive(:error)

          expect { perform_job }.not_to raise_error

          expect(Dependabot.logger).to have_received(:info).with(/Connectivity check starting/)
          expect(Dependabot.logger).to have_received(:error).with(/Connectivity check failed/)
        end
      end
    end
  end
end
