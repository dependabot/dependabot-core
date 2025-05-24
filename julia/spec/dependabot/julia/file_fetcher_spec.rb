# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Julia::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gps-silva/Example.jl",
      directory: directory,
      branch: "main"
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  context "with a basic Julia package" do
    let(:project_content) { fixture("projects", "basic", "Project.toml") }
    let(:manifest_content) { fixture("projects", "basic", "Manifest.toml") }

    before do
      allow(file_fetcher_instance).to receive(:fetch_file_content)
        .with("Project.toml")
        .and_return(project_content)

      allow(file_fetcher_instance).to receive(:fetch_file_content)
        .with("Manifest.toml")
        .and_return(manifest_content)
    end

    it "fetches the project and manifest files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Project.toml Manifest.toml))
    end
  end

  context "with multiple project files" do
    before do
      allow(file_fetcher_instance).to receive(:fetch_file_content)
        .and_raise(Octokit::NotFound)

      allow(file_fetcher_instance).to receive(:fetch_file_content)
        .with("Project.toml")
        .and_return("content")
      allow(file_fetcher_instance).to receive(:fetch_file_content)
        .with("JuliaProject.toml")
        .and_return("content")
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
        .with_message(/Multiple project files found/)
    end
  end

  # Add more test cases...
end
