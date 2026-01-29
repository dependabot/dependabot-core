# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pull_request_creator/message_components/multi_ecosystem_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::MultiEcosystemTitle do
  subject(:title) { builder.build }

  let(:builder) do
    described_class.new(
      dependencies: dependencies,
      source: source,
      credentials: credentials,
      **options
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:credentials) { github_credentials }
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [],
      previous_requirements: []
    )
  end
  let(:options) do
    {
      group_name: "production",
      security_fix: false,
      commit_message_options: {}
    }
  end

  before do
    stub_request(:get, "https://api.github.com/repos/gocardless/bump/commits?per_page=100")
      .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
  end

  describe "#build" do
    context "with a single dependency" do
      it "returns the correct title format" do
        expect(title).to eq('Bump the "production" group with 1 update across multiple ecosystems')
      end

      context "with security fix" do
        let(:options) { super().merge(security_fix: true) }

        it "includes security prefix" do
          expect(title).to start_with("[Security] Bump")
        end
      end
    end

    context "with multiple dependencies" do
      let(:dependency2) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "4.17.21",
          previous_version: "4.17.20",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependencies) { [dependency, dependency2] }

      it "shows the correct update count" do
        expect(title).to eq('Bump the "production" group with 2 updates across multiple ecosystems')
      end
    end

    context "with three dependencies" do
      let(:dependency2) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "4.17.21",
          previous_version: "4.17.20",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependency3) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.28.0",
          previous_version: "2.27.0",
          package_manager: "pip",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependencies) { [dependency, dependency2, dependency3] }

      it "shows the correct update count" do
        expect(title).to eq('Bump the "production" group with 3 updates across multiple ecosystems')
      end
    end

    context "with dependencies with the same name" do
      let(:dependency2) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.6.0",
          previous_version: "1.5.0",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependencies) { [dependency, dependency2] }

      it "counts unique dependencies" do
        expect(title).to eq('Bump the "production" group with 1 update across multiple ecosystems')
      end
    end

    context "with different group names" do
      let(:options) { super().merge(group_name: "development") }

      it "uses the correct group name" do
        expect(title).to eq('Bump the "development" group with 1 update across multiple ecosystems')
      end
    end

    context "without group name" do
      let(:options) { { security_fix: false, commit_message_options: {} } }

      it "uses default group name" do
        expect(title).to eq('Bump the "dependencies" group with 1 update across multiple ecosystems')
      end
    end

    context "with prefix from commit convention" do
      before do
        stub_request(:get, "https://api.github.com/repos/gocardless/bump/commits?per_page=100")
          .to_return(
            status: 200,
            body: fixture("github", "commits_angular.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "uses the commit prefix" do
        expect(title).to start_with("chore(deps):")
      end
    end
  end
end
