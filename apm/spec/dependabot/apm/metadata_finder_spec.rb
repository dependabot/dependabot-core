# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/apm/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Apm::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://github.com/microsoft/edge-ai" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "microsoft/edge-ai",
      version: "1.2.0",
      previous_version: "1.0.0",
      requirements: [{
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: { "type" => "git", "url" => url, "ref" => "v1.2.0", "branch" => nil }
      }],
      package_manager: "apm"
    )
  end

  before do
    # Not hosted on GitHub Enterprise Server
    stub_request(:get, "https://internal.example/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when the URL is a github one" do
      let(:url) { "https://github.com/microsoft/edge-ai" }

      it { is_expected.to eq("https://github.com/microsoft/edge-ai") }
    end

    context "when the URL is a gitlab one" do
      let(:url) { "https://gitlab.com/acme/prompts" }

      it { is_expected.to eq("https://gitlab.com/acme/prompts") }
    end

    context "when the URL is a deeply nested gitlab namespace" do
      let(:url) { "https://gitlab.com/group/subgroup/team/project" }

      it "preserves the full repository path instead of truncating it" do
        expect(source_url).to eq("https://gitlab.com/group/subgroup/team/project")
      end
    end

    context "when a github URL carries a custom port" do
      let(:url) { "https://github.com:8443/microsoft/edge-ai" }

      it "preserves the port instead of misreading it as the repository" do
        expect(source_url).to eq("https://github.com:8443/microsoft/edge-ai")
      end
    end

    context "when a nested gitlab URL carries a custom port" do
      let(:url) { "https://gitlab.com:8443/group/subgroup/project" }

      it "preserves both the port and the full repository path" do
        expect(source_url).to eq("https://gitlab.com:8443/group/subgroup/project")
      end
    end

    context "when the URL is from an unknown host" do
      let(:url) { "https://internal.example/team/skills" }

      it { is_expected.to be_nil }
    end
  end
end
