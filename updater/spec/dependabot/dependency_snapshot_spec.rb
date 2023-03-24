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
                    credentials: [],
                    reject_external_code?: false,
                    source: source,
                    experiments: { large_hadron_collider: true })
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

    context "when the job definition includes valid information prepared by the file fetcher step" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => encoded_dependency_files
        }
      end

      it "creates a new instance which has parsed the dependencies from the provided files" do
        snapshot = create_dependency_snapshot

        expect(snapshot).to be_a(described_class)
        expect(snapshot.base_commit_sha).to eql("mock-sha")
        expect(snapshot.dependency_files).to all(be_a(Dependabot::DependencyFile))
        expect(snapshot.dependency_files.map(&:content)).to eql(dependency_files.map(&:content))
        expect(snapshot.dependencies.count).to eql(2)
        expect(snapshot.dependencies).to all(be_a(Dependabot::Dependency))
        expect(snapshot.dependencies.map(&:name)).to eql(["dummy-pkg-a", "dummy-pkg-b"])
      end

      it "passes any job experiments on to the FileParser it instantiates as options" do
        expect(Dependabot::Bundler::FileParser).to receive(:new).with(
          dependency_files: anything,
          repo_contents_path: nil,
          source: source,
          credentials: [],
          reject_external_code: false,
          options: { large_hadron_collider: true }
        ).and_call_original

        create_dependency_snapshot
      end
    end

    context "when there is a parser error" do
      let(:job_definition) do
        {
          "base_commit_sha" => base_commit_sha,
          "base64_dependency_files" => encoded_dependency_files.tap do |files|
            files.first["content"] = Base64.encode64("garbage")
          end
        }
      end

      it "raises an error" do
        expect { create_dependency_snapshot }.to raise_error(Dependabot::DependencyFileNotEvaluatable)
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
