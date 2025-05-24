# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Julia::FileFetcher do
  let(:credentials) do
    # Basic git credentials for testing - the file fetcher uses these for repository access
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  # let(:github_url) { "https://api.github.com/" } # Not used in simplified spec
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil # repo_contents_path is optional for testing
    )
  end
  let(:source) do
    # Standard test source configuration for Julia repository
    Dependabot::Source.new(
      provider: "github",
      repo: "gps-babel/fake",
      directory: directory,
      branch: "main"
    )
  end

  # Test that the FileFetcher implements the required interface from the base class
  # If this fails, it indicates missing or incorrectly implemented methods
  it_behaves_like "a dependency file fetcher"

  describe "#fetch_files" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    before do
      # Enable beta ecosystems for all tests
      allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(true)
    end

    context "with empty repository (no files)" do
      before do
        allow(file_fetcher_instance).to receive(:fetch_file_if_present).and_return(nil)
      end

      it "raises an error when no Project.toml found" do
        expect do
          fetched_files
        end.to raise_error(Dependabot::DependencyFileNotFound, /No Project\.toml or JuliaProject\.toml found/)
      end
    end
  end

  describe "#fetch_files with mocked repository" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    before do
      # Enable beta ecosystems for all tests
      allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(true)

      # Mock the repository content responses
      allow(file_fetcher_instance).to receive(:fetch_file_if_present)
        .with("Project.toml")
        .and_return(project_file)
      allow(file_fetcher_instance).to receive(:fetch_file_if_present)
        .with("JuliaProject.toml")
        .and_return(nil)
      allow(file_fetcher_instance).to receive(:fetch_file_if_present)
        .with("Manifest.toml")
        .and_return(manifest_file)
      allow(file_fetcher_instance).to receive(:fetch_file_if_present)
        .with("JuliaManifest.toml")
        .and_return(nil)
    end

    let(:project_file) do
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: fixture("projects", "basic", "Project.toml")
      )
    end

    let(:manifest_file) do
      Dependabot::DependencyFile.new(
        name: "Manifest.toml",
        content: fixture("projects", "basic", "Manifest.toml")
      )
    end

    context "when both Project.toml and Manifest.toml exist" do
      it "fetches both files" do
        expect(fetched_files.map(&:name)).to contain_exactly("Project.toml", "Manifest.toml")
      end
    end

    context "when only Project.toml exists" do
      let(:manifest_file) { nil }

      it "fetches only Project.toml" do
        expect(fetched_files.map(&:name)).to eq(["Project.toml"])
      end
    end

    context "when beta ecosystems are disabled" do
      before do
        allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "returns empty array without fetching files" do
        expect(fetched_files).to eq([])
      end
    end
  end

  describe ".required_files_in?" do
    it "returns true when Project.toml is present" do
      expect(described_class.required_files_in?(["Project.toml"])).to be(true)
    end

    it "returns true when JuliaProject.toml is present" do
      expect(described_class.required_files_in?(["JuliaProject.toml"])).to be(true)
    end

    it "returns true with mixed case" do
      expect(described_class.required_files_in?(["project.toml"])).to be(true)
    end

    it "returns false when no Julia project files are present" do
      expect(described_class.required_files_in?(["package.json", "Gemfile"])).to be(false)
    end

    it "returns true when project file is present among other files" do
      files = ["README.md", "Project.toml", "src/MyPackage.jl"]
      expect(described_class.required_files_in?(files)).to be(true)
    end
  end

  describe ".required_files_message" do
    it "returns informative error message" do
      message = described_class.required_files_message
      expect(message).to include("Project.toml")
      expect(message).to be_a(String)
      expect(message.length).to be > 10
    end
  end

  private

  def fixture(type, *names)
    File.read(File.join("spec", "fixtures", type, *names))
  end
end
