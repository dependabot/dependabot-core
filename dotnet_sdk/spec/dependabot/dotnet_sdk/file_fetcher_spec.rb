# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::DotnetSdk::FileFetcher do
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/dotnet-sdk-example",
      directory: directory
    )
  end

  it_behaves_like "a dependency file fetcher"

  context "with a global.json in repo root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(global.json))
    end
  end

  context "with a directory that doesn't exist" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/src" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
        .with_message("global.json not found in /src")
    end
  end
end
