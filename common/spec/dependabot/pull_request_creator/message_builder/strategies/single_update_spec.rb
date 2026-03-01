# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/strategies/single_update"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::Strategies::SingleUpdate do
  subject(:strategy) do
    described_class.new(dependencies: dependencies, files: files)
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

  describe "#base_title" do
    context "with a single application dependency" do
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

      it "returns bump title with versions" do
        expect(strategy.base_title).to eq("bump business from 1.4.0 to 1.5.0")
      end
    end

    context "with a single library dependency" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "business.gemspec",
            content: "spec.add_dependency 'business'",
            directory: "/"
          )
        ]
      end

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [{ file: "business.gemspec", requirement: "~> 1.5.0", groups: [], source: nil }],
            previous_requirements: [{ file: "business.gemspec", requirement: "~> 1.4.0", groups: [], source: nil }]
          )
        ]
      end

      it "returns update title with requirements" do
        expect(strategy.base_title).to eq("update business requirement from ~> 1.4.0 to ~> 1.5.0")
      end
    end

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

      it "returns title with both names" do
        expect(strategy.base_title).to eq("bump business and statesman")
      end
    end

    context "with a non-root directory" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: "gem 'business'",
            directory: "/app"
          )
        ]
      end

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

      it "appends the directory" do
        expect(strategy.base_title).to eq("bump business from 1.4.0 to 1.5.0 in /app")
      end
    end
  end
end
