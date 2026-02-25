# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/strategies/group_update"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::Strategies::GroupUpdate do
  subject(:strategy) do
    described_class.new(
      dependencies: dependencies,
      files: files,
      dependency_group: dependency_group,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end

  let(:files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: "gem 'business'",
        directory: "/"
      )
    ]
  end

  let(:dependency_group) do
    Dependabot::DependencyGroup.new(name: "ruby-deps", rules: { "patterns" => ["*"] })
  end

  describe "#base_title" do
    context "with multiple dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
          ),
          Dependabot::Dependency.new(
            name: "statesman",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "bundler",
            requirements: [{ file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 1.0.0", groups: [], source: nil }]
          )
        ]
      end

      it "returns grouped title with update count" do
        expect(strategy.base_title).to eq(
          "bump the ruby-deps group with 2 updates"
        )
      end
    end

    context "with a single dependency" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
          )
        ]
      end

      it "returns solo title in the group" do
        expect(strategy.base_title).to eq(
          "bump business from 1.4.0 to 1.5.0 in the ruby-deps group"
        )
      end
    end

    context "with multi-directory source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directories: ["/app", "/lib"]
        )
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }],
            metadata: { directory: "/app" }
          ),
          Dependabot::Dependency.new(
            name: "statesman",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "bundler",
            requirements: [{ file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil }],
            previous_requirements: [{ file: "Gemfile", requirement: "~> 1.0.0", groups: [], source: nil }],
            metadata: { directory: "/lib" }
          )
        ]
      end

      it "returns multi-directory grouped title" do
        expect(strategy.base_title).to eq(
          "bump the ruby-deps group across 2 directories with 2 updates"
        )
      end
    end
  end
end
