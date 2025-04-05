# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GoModules::FileFetcher do
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: github_credentials,
                        repo_contents_path: repo_contents_path)
  end
  let(:repo_contents_path) { Dir.mktmpdir }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: directory,
      branch: branch
    )
  end
  let(:branch) { "master" }
  let(:repo) { "dependabot-fixtures/go-modules-lib" }

  after do
    FileUtils.rm_rf(repo_contents_path)
  end

  it_behaves_like "a dependency file fetcher"

  it "fetches the go.mod and go.sum" do
    expect(file_fetcher_instance.files.map(&:name))
      .to include("go.mod", "go.sum")
  end

  it "provides the Go modules version" do
    expect(file_fetcher_instance.ecosystem_versions).to eq({
      package_managers: { "gomod" => "unknown" }
    })
  end

  context "without a go.mod" do
    let(:branch) { "without-go-mod" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "without a go.sum" do
    let(:branch) { "without-go-sum" }

    it "doesn't raise an error" do
      expect { file_fetcher_instance.files }.not_to raise_error
    end
  end

  context "when directory is missing" do
    let(:directory) { "/missing" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "when dependencies are git submodules" do
    let(:repo) { "dependabot-fixtures/go-modules-app-with-git-submodules" }
    let(:branch) { "main" }
    let(:submodule_contents_path) { File.join(repo_contents_path, "examplelib") }

    it "clones them" do
      expect { file_fetcher_instance.files }.not_to raise_error
      expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
    end

    it "provides the Go modules version" do
      expect(file_fetcher_instance.ecosystem_versions).to eq({
        package_managers: { "gomod" => "1.19" }
      })
    end
  end
end
