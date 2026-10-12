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

  context "with a go.work workspace" do
    let(:repo_contents_path) { build_tmp_repo("workspace") }
    let(:file_fetcher_instance) do
      described_class.new(
        source: source,
        credentials: github_credentials,
        repo_contents_path: repo_contents_path
      )
    end

    before do
      allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
    end

    after do
      FileUtils.rm_rf(repo_contents_path)
    end

    it "fetches go.work" do
      expect(file_fetcher_instance.files.map(&:name)).to include("go.work")
    end

    it "fetches module files for all workspace entries" do
      file_names = file_fetcher_instance.files.map(&:name)
      expect(file_names).to include("go.mod")
      expect(file_names).to include("libs/go.mod")
      expect(file_names).to include("services/go.mod")
    end

    it "fetches go.sum files from workspace modules" do
      file_names = file_fetcher_instance.files.map(&:name)
      expect(file_names).to include("go.sum")
      expect(file_names).to include("libs/go.sum")
      expect(file_names).to include("services/go.sum")
    end
  end

  context "with a go.work workspace (no root module)" do
    let(:repo_contents_path) { build_tmp_repo("workspace_no_root_mod") }
    let(:file_fetcher_instance) do
      described_class.new(
        source: source,
        credentials: github_credentials,
        repo_contents_path: repo_contents_path
      )
    end

    before do
      allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
    end

    after do
      FileUtils.rm_rf(repo_contents_path)
    end

    it "fetches go.work" do
      expect(file_fetcher_instance.files.map(&:name)).to include("go.work")
    end

    it "fetches sub-module go.mod files" do
      file_names = file_fetcher_instance.files.map(&:name)
      expect(file_names).to include("api/go.mod")
      expect(file_names).to include("worker/go.mod")
    end

    it "does not include a root go.mod" do
      file_names = file_fetcher_instance.files.map(&:name)
      expect(file_names).not_to include("go.mod")
    end

    it "does not raise when no root go.mod exists" do
      expect { file_fetcher_instance.files }.not_to raise_error
    end
  end

  context "with a root-only go.work workspace (use . only)" do
    let(:repo_contents_path) { build_tmp_repo("workspace_root_only") }
    let(:file_fetcher_instance) do
      described_class.new(
        source: source,
        credentials: github_credentials,
        repo_contents_path: repo_contents_path
      )
    end

    before do
      allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
    end

    after do
      FileUtils.rm_rf(repo_contents_path)
    end

    it "fetches go.work" do
      expect(file_fetcher_instance.files.map(&:name)).to include("go.work")
    end

    it "fetches the root go.mod exactly once" do
      mod_files = file_fetcher_instance.files.select { |f| f.name == "go.mod" }
      expect(mod_files.length).to eq(1)
    end

    it "does not raise" do
      expect { file_fetcher_instance.files }.not_to raise_error
    end
  end
end
