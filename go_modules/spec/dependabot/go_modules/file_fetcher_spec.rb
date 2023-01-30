# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GoModules::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:repo) { "dependabot-fixtures/go-modules-lib" }
  let(:branch) { "master" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: directory,
      branch: branch
    )
  end
  let(:repo_contents_path) { Dir.mktmpdir }
  after { FileUtils.rm_rf(repo_contents_path) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: github_credentials,
                        repo_contents_path: repo_contents_path)
  end
  let(:directory) { "/" }

  after do
    FileUtils.rm_rf(repo_contents_path)
  end

  it "fetches the go.mod and go.sum" do
    expect(file_fetcher_instance.files.map(&:name)).
      to include("go.mod", "go.sum")
  end

  context "when dependencies are git submodules" do
    let(:repo) { "dependabot-fixtures/go-modules-app-with-git-submodules" }
    let(:branch) { "main" }
    let(:submodule_contents_path) { File.join(repo_contents_path, "examplelib") }

    it "clones them" do
      expect { file_fetcher_instance.files }.to_not raise_error
      expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
    end
  end
end
