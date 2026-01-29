# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/message_components"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents do
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "test/repo")
  end
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
  let(:credentials) { [] }
  let(:files) { [] }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  before do
    stub_request(:get, watched_repo_url + "/commits?per_page=100")
      .to_return(status: 200, body: "[]", headers: json_header)
  end

  describe ".create_title" do
    context "with type: :single" do
      it "creates a SingleUpdateTitle component" do
        title = described_class.create_title(
          type: :single,
          dependencies: [dependency],
          source: source,
          credentials: credentials
        )

        expect(title).to be_a(Dependabot::PullRequestCreator::MessageComponents::SingleUpdateTitle)
        expect(title.build).to eq("Bump business from 1.4.0 to 1.5.0")
      end
    end

    context "with type: :group" do
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "test-group", rules: { patterns: ["*"] })
      end

      it "creates a GroupUpdateTitle component" do
        title = described_class.create_title(
          type: :group,
          dependencies: [dependency],
          source: source,
          credentials: credentials,
          dependency_group: dependency_group
        )

        expect(title).to be_a(Dependabot::PullRequestCreator::MessageComponents::GroupUpdateTitle)
        expect(title.build).to eq("Bump business from 1.4.0 to 1.5.0 in the test-group group")
      end
    end

    context "with type: :multi_ecosystem" do
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "all-deps", rules: { patterns: ["*"] })
      end

      it "creates a MultiEcosystemTitle component" do
        title = described_class.create_title(
          type: :multi_ecosystem,
          dependencies: [dependency],
          source: source,
          credentials: credentials,
          dependency_group: dependency_group
        )

        expect(title).to be_a(Dependabot::PullRequestCreator::MessageComponents::MultiEcosystemTitle)
        expect(title.build).to eq("Bump business in the all-deps group across multiple ecosystems")
      end
    end

    context "with unknown type" do
      it "raises an ArgumentError" do
        expect do
          described_class.create_title(
            type: :unknown,
            dependencies: [dependency],
            source: source,
            credentials: credentials
          )
        end.to raise_error(ArgumentError, /Unknown title type: unknown/)
      end
    end
  end
end
