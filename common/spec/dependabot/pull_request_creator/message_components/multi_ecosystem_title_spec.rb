# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/message_components/multi_ecosystem_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::MultiEcosystemTitle do
  subject(:title_builder) do
    described_class.new(
      dependencies: dependencies,
      source: source,
      credentials: credentials,
      files: files,
      vulnerabilities_fixed: vulnerabilities_fixed,
      commit_message_options: commit_message_options,
      dependency_group: dependency_group
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements: [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:files) { [] }
  let(:credentials) { [] }
  let(:vulnerabilities_fixed) { {} }
  let(:commit_message_options) { {} }
  let(:dependency_group) do
    Dependabot::DependencyGroup.new(name: "all-deps", rules: { patterns: ["*"] })
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  describe "#base_title" do
    subject(:base_title) { title_builder.base_title }

    before do
      stub_request(:get, watched_repo_url + "/commits?per_page=100")
        .to_return(status: 200, body: "[]", headers: json_header)
    end

    context "with a single dependency" do
      it "mentions multi-ecosystem" do
        expect(base_title).to eq("bump business in the all-deps group across multiple ecosystems")
      end
    end

    context "with multiple dependencies" do
      let(:dependency2) do
        Dependabot::Dependency.new(
          name: "rails",
          version: "7.0.0",
          previous_version: "6.0.0",
          package_manager: "npm",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependencies) { [dependency, dependency2] }

      it "includes update count" do
        expect(base_title).to eq("bump the all-deps group with 2 updates across multiple ecosystems")
      end
    end

    context "without a dependency group" do
      let(:dependency_group) { nil }

      it "uses 'dependencies' as default group name" do
        expect(base_title).to eq("bump business in the dependencies group across multiple ecosystems")
      end
    end
  end

  describe "#build" do
    subject(:title) { title_builder.build }

    before do
      stub_request(:get, watched_repo_url + "/commits?per_page=100")
        .to_return(status: 200, body: "[]", headers: json_header)
    end

    it "returns the complete title with capitalization" do
      expect(title).to eq("Bump business in the all-deps group across multiple ecosystems")
    end
  end
end
