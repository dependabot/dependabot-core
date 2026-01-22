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

    let(:registry_client) { instance_double(Dependabot::Julia::RegistryClient) }
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

    before do
      # Mock the registry client
      allow(file_fetcher_instance).to receive(:registry_client).and_return(registry_client)

      # Mock SharedHelpers to avoid actual repo cloning
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_repo_directory).and_yield("/tmp/test")
    end

    context "when Julia helper finds Project.toml and Manifest.toml" do
      before do
        allow(registry_client).to receive(:find_workspace_project_files)
          .with("/tmp/test")
          .and_return({
            "project_files" => ["/tmp/test/Project.toml"],
            "manifest_file" => "/tmp/test/Manifest.toml",
            "workspace_root" => "/tmp/test"
          })

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Project.toml")
          .and_return(project_file)

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Manifest.toml")
          .and_return(manifest_file)

        allow(File).to receive(:exist?).and_return(true)
      end

      it "fetches both files" do
        expect(fetched_files.map(&:name)).to contain_exactly("Project.toml", "Manifest.toml")
      end
    end

    context "when Julia helper finds only Project.toml" do
      before do
        allow(registry_client).to receive(:find_workspace_project_files)
          .with("/tmp/test")
          .and_return({
            "project_files" => ["/tmp/test/Project.toml"],
            "manifest_file" => "",
            "workspace_root" => "/tmp/test"
          })

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Project.toml")
          .and_return(project_file)
      end

      it "fetches only Project.toml" do
        expect(fetched_files.map(&:name)).to eq(["Project.toml"])
      end
    end

    context "when Julia helper finds workspace with multiple Project.toml files" do
      let(:docs_project_file) do
        Dependabot::DependencyFile.new(
          name: "docs/Project.toml",
          content: "name = \"DocsProject\""
        )
      end

      let(:test_project_file) do
        Dependabot::DependencyFile.new(
          name: "test/Project.toml",
          content: "name = \"TestProject\""
        )
      end

      before do
        allow(registry_client).to receive(:find_workspace_project_files)
          .with("/tmp/test")
          .and_return({
            "project_files" => [
              "/tmp/test/Project.toml",
              "/tmp/test/docs/Project.toml",
              "/tmp/test/test/Project.toml"
            ],
            "manifest_file" => "/tmp/test/Manifest.toml",
            "workspace_root" => "/tmp/test"
          })

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Project.toml")
          .and_return(project_file)

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("docs/Project.toml")
          .and_return(docs_project_file)

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("test/Project.toml")
          .and_return(test_project_file)

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Manifest.toml")
          .and_return(manifest_file)

        allow(File).to receive(:exist?).and_return(true)
      end

      it "fetches all Project.toml files and the manifest" do
        expect(fetched_files.map(&:name)).to contain_exactly(
          "Project.toml",
          "docs/Project.toml",
          "test/Project.toml",
          "Manifest.toml"
        )
      end
    end

    context "when Julia helper finds versioned manifest" do
      let(:versioned_manifest_file) do
        Dependabot::DependencyFile.new(
          name: "Manifest-v1.12.toml",
          content: fixture("projects", "basic", "Manifest.toml")
        )
      end

      before do
        allow(registry_client).to receive(:find_workspace_project_files)
          .with("/tmp/test")
          .and_return({
            "project_files" => ["/tmp/test/Project.toml"],
            "manifest_file" => "/tmp/test/Manifest-v1.12.toml",
            "workspace_root" => "/tmp/test"
          })

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Project.toml")
          .and_return(project_file)

        allow(file_fetcher_instance).to receive(:fetch_file_if_present)
          .with("Manifest-v1.12.toml")
          .and_return(versioned_manifest_file)

        allow(File).to receive(:exist?).and_return(true)
      end

      it "fetches both files including versioned manifest" do
        expect(fetched_files.map(&:name)).to contain_exactly("Project.toml", "Manifest-v1.12.toml")
      end
    end

    context "when no Project.toml found" do
      before do
        allow(registry_client).to receive(:find_workspace_project_files)
          .with("/tmp/test")
          .and_return({ "error" => "No project file found", "project_files" => [] })
      end

      it "raises an error" do
        expect do
          fetched_files
        end.to raise_error(Dependabot::DependencyFileNotFound, /No Project\.toml or JuliaProject\.toml found/)
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
