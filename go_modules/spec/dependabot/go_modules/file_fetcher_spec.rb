# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GoModules::FileFetcher do
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: github_credentials,
      repo_contents_path: repo_contents_path
    )
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
    expect(file_fetcher_instance.ecosystem_versions).to eq(
      {
        package_managers: { "gomod" => "unknown" }
      }
    )
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

  context "with a go.env file" do
    let(:branch) { "with-go-env" }

    it "fetches the go.env file" do
      expect(file_fetcher_instance.files.map(&:name)).to include("go.env")
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
      expect(file_fetcher_instance.ecosystem_versions).to eq(
        {
          package_managers: { "gomod" => "1.19" }
        }
      )
    end
  end

  context "with a go.work file (workspace mode)" do
    let(:branch) { "with-workspace" }

    before do
      # Set up workspace fixture
      workspace_path = File.join(repo_contents_path, directory)
      FileUtils.mkdir_p(workspace_path)

      # Copy workspace fixture
      fixture_path = File.join(__dir__, "../../fixtures/projects/workspace")
      FileUtils.cp_r("#{fixture_path}/.", workspace_path)

      # Stub the file listing to include go.work
      allow(file_fetcher_instance).to receive(:repo_contents)
        .and_return(
          Dependabot::FileFetchers::Base::RepoContents.new(
            repo_contents_path,
            directory,
            github_credentials
          )
        )
    end

    it "fetches the go.work file" do
      files = file_fetcher_instance.files
      expect(files.map(&:name)).to include("go.work")
    end

    it "fetches all workspace module go.mod files" do
      files = file_fetcher_instance.files
      expect(files.map(&:name)).to include(
        "go.mod",
        "tools/go.mod",
        "api/go.mod"
      )
    end

    it "fetches all workspace module go.sum files" do
      files = file_fetcher_instance.files
      expect(files.map(&:name)).to include(
        "go.sum",
        "tools/go.sum",
        "api/go.sum"
      )
    end
  end
end
