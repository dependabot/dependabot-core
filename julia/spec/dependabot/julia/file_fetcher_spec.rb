# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Julia::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gps-babel/fake",
      directory: directory,
      branch: "main" # Assuming a default branch for stubbing
    )
  end

  it_behaves_like "a dependency file fetcher"

  context "with a basic Julia package" do
    let(:project_content) { fixture("projects", "basic", "Project.toml") }
    let(:manifest_content) { fixture("projects", "basic", "Manifest.toml") }
    let(:project_url) { "https://api.github.com/repos/gps-babel/fake/contents/Project.toml?ref=main" }
    let(:manifest_url) { "https://api.github.com/repos/gps-babel/fake/contents/Manifest.toml?ref=main" }

    before do
      # Stub SharedHelpers.run_shell_command for Julia version detection if it's called
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("julia --version", allow_unsafe_shell_command: true)
        .and_return("julia version 1.6.0") # Example version

      stub_request(:get, project_url)
        .to_return(status: 200, body: { content: Base64.encode64(project_content) }.to_json, headers: { "content-type" => "application/json" })
      stub_request(:get, manifest_url)
        .to_return(status: 200, body: { content: Base64.encode64(manifest_content) }.to_json, headers: { "content-type" => "application/json" })

      # Remove or adjust the direct stubbing of fetch_file_content if it's no longer needed
      # allow(file_fetcher_instance).to receive(:fetch_file_content)
      #   .with("Project.toml")
      #   .and_return(project_content)

      # allow(file_fetcher_instance).to receive(:fetch_file_content)
      #   .with("Manifest.toml")
      #   .and_return(manifest_content)
    end

    it "fetches the project and manifest files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Project.toml Manifest.toml))
    end
  end

  context "with multiple project files" do
    let(:project_content) { "name = \"TestProject\"" }
    let(:project_url) { "https://api.github.com/repos/gps-babel/fake/contents/Project.toml?ref=main" }
    let(:julia_project_url) { "https://api.github.com/repos/gps-babel/fake/contents/JuliaProject.toml?ref=main" }
    # Assume Manifest.toml might be looked for and not found, or found
    let(:manifest_url) { "https://api.github.com/repos/gps-babel/fake/contents/Manifest.toml?ref=main" }


    before do
      # Stub SharedHelpers.run_shell_command for Julia version detection
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("julia --version", allow_unsafe_shell_command: true)
        .and_return("julia version 1.6.0") # Example version

      # Stub to simulate finding both Project.toml and JuliaProject.toml
      stub_request(:get, project_url)
        .to_return(status: 200, body: { content: Base64.encode64(project_content) }.to_json, headers: { "content-type" => "application/json" })
      stub_request(:get, julia_project_url)
        .to_return(status: 200, body: { content: Base64.encode64(project_content) }.to_json, headers: { "content-type" => "application/json" })

      # Stub for Manifest.toml (e.g., not found, or found if needed by the test logic)
      stub_request(:get, manifest_url)
        .to_return(status: 404)


      # Remove or adjust direct stubbing of fetch_file_content
      # allow(file_fetcher_instance).to receive(:fetch_file_content)
      #   .and_raise(Octokit::NotFound) # This might be too broad

      # allow(file_fetcher_instance).to receive(:fetch_file_content)
      #   .with("Project.toml")
      #   .and_return("content")
      # allow(file_fetcher_instance).to receive(:fetch_file_content)
      #   .with("JuliaProject.toml")
      #   .and_return("content")
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
        .with_message(/Multiple project files found/)
    end
  end

  # Add more test cases...
end
