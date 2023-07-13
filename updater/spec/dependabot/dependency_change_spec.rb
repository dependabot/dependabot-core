# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_change"
require "dependabot/job"

RSpec.describe Dependabot::DependencyChange do
  subject(:dependency_change) do
    described_class.new(
      job: job,
      updated_dependencies: updated_dependencies,
      updated_dependency_files: updated_dependency_files
    )
  end

  let(:job) do
    instance_double(Dependabot::Job)
  end

  let(:updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        previous_version: "1.7.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }
        ]
      )
    ]
  end

  let(:updated_dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  describe "#pr_message" do
    let(:github_source) do
      {
        "provider" => "github",
        "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
        "directory" => "/",
        "branch" => nil,
        "api-endpoint" => "https://api.github.com/",
        "hostname" => "github.com"
      }
    end

    let(:job_credentials) do
      [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        },
        { "type" => "random", "secret" => "codes" }
      ]
    end

    let(:commit_message_options) do
      {
        include_scope: true,
        prefix: "[bump]",
        prefix_development: "[bump-dev]"
      }
    end

    let(:message_builder_mock) do
      instance_double(Dependabot::PullRequestCreator::MessageBuilder, message: "Hello World!")
    end

    before do
      allow(job).to receive(:source).and_return(github_source)
      allow(job).to receive(:credentials).and_return(job_credentials)
      allow(job).to receive(:commit_message_options).and_return(commit_message_options)
      allow(Dependabot::PullRequestCreator::MessageBuilder).to receive(:new).and_return(message_builder_mock)
    end

    it "delegates to the Dependabot::PullRequestCreator::MessageBuilder with the correct configuration" do
      expect(Dependabot::PullRequestCreator::MessageBuilder).
        to receive(:new).with(
          source: github_source,
          files: updated_dependency_files,
          dependencies: updated_dependencies,
          credentials: job_credentials,
          commit_message_options: commit_message_options,
          dependency_group: nil
        )

      expect(dependency_change.pr_message).to eql("Hello World!")
    end

    context "when a dependency group is assigned" do
      it "delegates to the Dependabot::PullRequestCreator::MessageBuilder with the group included" do
        group = Dependabot::DependencyGroup.new(name: "foo", rules: { patterns: ["*"] })

        dependency_change = described_class.new(
          job: job,
          updated_dependencies: updated_dependencies,
          updated_dependency_files: updated_dependency_files,
          dependency_group: group
        )

        expect(Dependabot::PullRequestCreator::MessageBuilder).
          to receive(:new).with(
            source: github_source,
            files: updated_dependency_files,
            dependencies: updated_dependencies,
            credentials: job_credentials,
            commit_message_options: commit_message_options,
            dependency_group: group
          )

        expect(dependency_change.pr_message).to eql("Hello World!")
      end
    end
  end

  describe "#grouped_update?" do
    it "is false by default" do
      expect(dependency_change.grouped_update?).to be false
    end

    context "when a dependency group is assigned" do
      it "is true" do
        dependency_change = described_class.new(
          job: job,
          updated_dependencies: updated_dependencies,
          updated_dependency_files: updated_dependency_files,
          dependency_group: Dependabot::DependencyGroup.new(name: "foo", rules: { patterns: ["*"] })
        )

        expect(dependency_change.grouped_update?).to be true
      end
    end
  end
end
