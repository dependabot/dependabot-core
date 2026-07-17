# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GithubActions::MetadataFinder do
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
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/actions/checkout",
      ref: "master",
      branch: nil
    }
  end
  let(:dependency_name) { "actions/checkout" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source
      }],
      package_manager: "github_actions"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when dealing with a git source" do
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "master",
          branch: nil
        }
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }
    end

    context "when dealing with a subdependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: nil,
          requirements: [],
          package_manager: "github_actions"
        )
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }
    end

    context "when dealing with a subdependency on GHE" do
      # Simulates GitCommitChecker calling look_up_source with a subdependency
      # (empty requirements) when the job is configured with GHE source
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "mycompany.com",
          "username" => "x-access-token",
          "password" => "token"
        }]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: nil,
          requirements: [],
          package_manager: "github_actions"
        )
      end

      before do
        stub_request(:get, "https://mycompany.com/status")
          .to_return(
            status: 200,
            headers: { "X-GitHub-Request-Id" => "12345" }
          )
      end

      it { is_expected.to eq("https://mycompany.com/actions/checkout") }
    end
  end
end
