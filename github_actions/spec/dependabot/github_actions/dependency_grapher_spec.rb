# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/github_actions"

RSpec.describe Dependabot::GithubActions::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("github_actions").new(
      file_parser: parser
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/.github/workflows"
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("github_actions").new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:ci_workflow) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/ci.yml",
      content: <<~YAML
        name: CI
        on: [push]
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: actions/setup-node@v4
      YAML
    )
  end

  let(:release_workflow) do
    Dependabot::DependencyFile.new(
      name: ".github/workflows/release.yml",
      content: <<~YAML
        name: Release
        on:
          release:
            types: [published]
        jobs:
          publish:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@v4
              - uses: actions/download-artifact@v4
      YAML
    )
  end

  def mock_service_pack_request(nwo, fixture_name)
    stub_request(:get, "https://github.com/#{nwo}.git/info/refs?service=git-upload-pack")
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", fixture_name),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  before do
    mock_service_pack_request("actions/checkout", "checkout")
    mock_service_pack_request("actions/setup-node", "setup-node")
    mock_service_pack_request("actions/download-artifact", "download-artifact")
  end

  describe "#manifest_group_snapshots" do
    context "when a directory contains multiple workflow files" do
      # Ordered alphabetically, exactly as the GitHub API returns directory contents. `ci.yml` sorts first,
      # so it would be the collapse target under the old whole-directory heuristic.
      let(:dependency_files) { [ci_workflow, release_workflow] }

      it "produces one manifest group per workflow file rather than collapsing onto the first" do
        manifest_names = grapher.manifest_group_snapshots.map { |snapshot| snapshot.manifest_file.name }

        expect(manifest_names).to contain_exactly(
          ".github/workflows/ci.yml",
          ".github/workflows/release.yml"
        )
      end

      it "attributes each action only to the workflow that actually uses it" do
        snapshots = grapher.manifest_group_snapshots.to_h do |snapshot|
          [snapshot.manifest_file.name, snapshot.resolved_dependencies.keys]
        end

        expect(snapshots.fetch(".github/workflows/ci.yml")).to contain_exactly(
          "pkg:github/actions/checkout@4",
          "pkg:github/actions/setup-node@4"
        )
        expect(snapshots.fetch(".github/workflows/release.yml")).to contain_exactly(
          "pkg:github/actions/checkout@4",
          "pkg:github/actions/download-artifact@4"
        )
      end

      it "reports a shared action against every workflow that uses it" do
        checkout_owners = grapher.manifest_group_snapshots.filter_map do |snapshot|
          snapshot.manifest_file.name if snapshot.resolved_dependencies.key?("pkg:github/actions/checkout@4")
        end

        expect(checkout_owners).to contain_exactly(
          ".github/workflows/ci.yml",
          ".github/workflows/release.yml"
        )
      end
    end

    context "when a directory contains a single workflow file" do
      let(:dependency_files) { [ci_workflow] }

      it "produces a single manifest group attributed to that file" do
        snapshots = grapher.manifest_group_snapshots

        expect(snapshots.length).to eq(1)
        expect(snapshots.first.manifest_file.name).to eq(".github/workflows/ci.yml")
        expect(snapshots.first.resolved_dependencies.keys).to contain_exactly(
          "pkg:github/actions/checkout@4",
          "pkg:github/actions/setup-node@4"
        )
      end
    end
  end
end
