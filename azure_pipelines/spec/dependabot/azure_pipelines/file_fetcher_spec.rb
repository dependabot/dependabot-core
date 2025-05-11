# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::AzurePipelines::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/azure-pipelines-example",
      directory: directory
    )
  end
  let(:directory) { "/" }

  it_behaves_like "a dependency file fetcher"

  context "with an azure-pipelines.yml in repo root" do
    let(:project_name) { "file_in_root" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(azure-pipelines.yml))
    end
  end

  context "with an azure-pipelines.yml in a subdirectory" do
    let(:project_name) { "nested_file" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.azure-pipelines/azure-pipelines.yml))
    end
  end

  context "with multiple azure-pipelines.yml files" do
    let(:project_name) { "multiple_files" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(azure-pipelines.yml .azure-pipelines/azure-pipelines.yml))
    end
  end

  context "with a directory that doesn't exist" do
    let(:project_name) { "file_in_root" }
    let(:directory) { "/src" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
        .with_message("No Azure Pipelines files found in /src")
    end
  end

  context "without a global.json in repo root" do
    let(:project_name) { "no_file" }

    it "returns an empty array" do
      expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
