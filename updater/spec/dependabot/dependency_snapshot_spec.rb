# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_snapshot"
require "dependabot/job"

RSpec.describe Dependabot::DependencySnapshot do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directory: "/",
      branch: nil,
      api_endpoint: "https://api.github.com/",
      hostname: "github.com"
    )
  end

  let(:job) do
    instance_double(Dependabot::Job,
                    package_manager: "bundler",
                    repo_contents_path: nil,
                    credentials: {},
                    reject_external_code?: false,
                    source: source,
                    experiments: {})
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  let(:base_commit_sha) do
    "mock-sha"
  end

  describe "::create_from_job_definition" do
    subject(:create_dependency_snapshot) do
      described_class.create_from_job_definition(
        job: job,
        job_definition: job_definition
      )
    end

    let(:encoded_dependency_files) do
      dependency_files.map do |file|
        base64_file = file.dup
        base64_file.content = Base64.encode64(file.content)
        base64_file.to_h
      end
    end

    context "when the job definition does not have the 'base64_dependency_files' key" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(KeyError)
      end
    end

    context "when the job definition does not have the 'base_commit_sha' key" do
      let(:job_definition) do
        {
          "base64_dependency_files" => encoded_dependency_files
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(KeyError)
      end
    end
  end
end
