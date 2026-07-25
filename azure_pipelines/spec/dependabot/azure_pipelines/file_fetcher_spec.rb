# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/experiments"
require "dependabot/source"
require "dependabot/azure_pipelines/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::AzurePipelines::FileFetcher do
  let(:file_fetcher) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: nil)
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    )]
  end
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: directory)
  end
  let(:contents_url) { "https://api.github.com/repos/gocardless/bump/contents/" }

  def stub_directory(path, entries)
    url = path.empty? ? contents_url : "#{contents_url}#{path}"
    stub_request(:get, "#{url}?ref=sha")
      .to_return(status: 200, body: JSON.dump(entries), headers: { "content-type" => "application/json" })
  end

  def entry(name, type: "file", path: nil)
    { "name" => name, "path" => path || name, "type" => type }
  end

  def stub_file(path, fixture_path)
    stub_request(:get, "#{contents_url}#{path}?ref=sha")
      .to_return(
        status: 200,
        body: JSON.dump(
          "name" => File.basename(path),
          "path" => path,
          "type" => "file",
          "content" => Base64.encode64(fixture(*fixture_path)),
          "encoding" => "base64"
        ),
        headers: { "content-type" => "application/json" }
      )
  end

  before do
    Dependabot::Experiments.register(:enable_beta_ecosystems, true)
    allow(file_fetcher).to receive(:commit).and_return("sha")
  end

  after { Dependabot::Experiments.reset! }

  it_behaves_like "a dependency file fetcher"

  describe "#fetch_files" do
    context "with a pipeline in the repository root" do
      before do
        stub_directory("", [entry("azure-pipelines.yml"), entry("README.md")])
        stub_file("azure-pipelines.yml", ["projects", "simple", "azure-pipelines.yml"])
      end

      it "fetches the pipeline" do
        expect(file_fetcher.files.map(&:name)).to eq(["azure-pipelines.yml"])
      end
    end

    context "with a pipeline in a subdirectory" do
      before do
        stub_directory("", [entry("README.md"), entry(".azure-pipelines", type: "dir")])
        stub_directory(".azure-pipelines", [entry("build.yml", path: ".azure-pipelines/build.yml")])
        stub_file(".azure-pipelines/build.yml", ["projects", "nested", ".azure-pipelines", "build.yml"])
      end

      it "finds it without relying on the file name" do
        expect(file_fetcher.files.map(&:name)).to eq([".azure-pipelines/build.yml"])
      end
    end

    context "with YAML that is not a pipeline" do
      before do
        stub_directory("", [entry("config.yml")])
        stub_file("config.yml", ["projects", "not_a_pipeline", "config.yml"])
      end

      it "raises DependencyFileNotFound" do
        expect { file_fetcher.files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with no YAML at all" do
      before { stub_directory("", [entry("README.md")]) }

      it "raises DependencyFileNotFound" do
        expect { file_fetcher.files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end

    context "with vendored YAML alongside a pipeline" do
      before do
        stub_directory("", [entry("azure-pipelines.yml"), entry("node_modules", type: "dir")])
        stub_file("azure-pipelines.yml", ["projects", "simple", "azure-pipelines.yml"])
      end

      it "does not descend into directories that never hold pipelines" do
        expect(file_fetcher.files.map(&:name)).to eq(["azure-pipelines.yml"])
        expect(WebMock).not_to have_requested(:get, "#{contents_url}node_modules?ref=sha")
      end
    end

    context "when nesting goes deeper than the search does" do
      before do
        stub_directory("", [entry("a", type: "dir")])
        stub_directory("a", [entry("b", type: "dir", path: "a/b")])
        stub_directory("a/b", [entry("c", type: "dir", path: "a/b/c")])
      end

      it "stops rather than walking the whole repository" do
        expect { file_fetcher.files }.to raise_error(Dependabot::DependencyFileNotFound)
        expect(WebMock).not_to have_requested(:get, "#{contents_url}a/b/c?ref=sha")
      end
    end

    context "when beta ecosystems are not enabled" do
      before do
        Dependabot::Experiments.reset!
        stub_directory("", [entry("azure-pipelines.yml")])
      end

      it "refuses to fetch anything" do
        expect { file_fetcher.files }.to raise_error(Dependabot::DependencyFileNotFound, /beta/)
      end
    end
  end

  describe ".required_files_in?" do
    it "accepts any YAML file" do
      expect(described_class.required_files_in?(["azure-pipelines.yml"])).to be(true)
      expect(described_class.required_files_in?(["ci/build.yaml"])).to be(true)
      expect(described_class.required_files_in?(["README.md"])).to be(false)
    end
  end
end
