# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/definition"

RSpec.describe Dependabot::Job::Definition do
  describe ".from_hash" do
    subject(:definition) { described_class.from_hash(attributes) }

    let(:attributes) do
      {
        id: "job-id",
        command: "update",
        allowed_updates: [{ "dependency-type" => "direct" }],
        commit_message_options: { "prefix" => "deps", "include-scope" => true },
        credentials: [{ "type" => "git_source", "host" => "github.com" }],
        dependencies: ["rake"],
        exclude_paths: ["vendor/**"],
        existing_pull_requests: [],
        existing_group_pull_requests: [{ "dependency-group-name" => "group-a" }],
        experiments: { "feature" => true, "timeout" => 60 },
        ignore_conditions: [{ "dependency-name" => "rake" }],
        package_manager: "bundler",
        reject_external_code: false,
        repo_contents_path: "/tmp/repo",
        requirements_update_strategy: nil,
        lockfile_only: false,
        security_advisories: [],
        security_updates_only: false,
        source: {
          "provider" => "github",
          "repo" => "dependabot/dependabot-core",
          "directory" => "/"
        },
        token: "token",
        update_subdependencies: false,
        updating_a_pull_request: false,
        vendor_dependencies: true,
        cooldown: { "default-days" => 7 },
        multi_ecosystem_update: false,
        dependency_groups: [{ "name" => "group-a" }],
        dependency_group_to_refresh: "group-a",
        repo_private: true,
        blocked_versions: [{ "dependency-name" => "rake", "version-requirement" => "< 1" }]
      }
    end

    it "parses the final constructor values" do
      expect(definition).to have_attributes(
        id: "job-id",
        command: "update",
        dependencies: ["rake"],
        exclude_paths: ["vendor/**"],
        package_manager: "bundler",
        repo_contents_path: "/tmp/repo",
        security_updates_only: false,
        token: "token",
        vendor_dependencies: true,
        dependency_group_to_refresh: "group-a",
        repo_private: true
      )
      expect(definition.allowed_updates).to all(be_a(Dependabot::Job::AllowedUpdate))
      expect(definition.credentials).to all(be_a(Dependabot::Credential))
      expect(definition.ignore_conditions).to all(be_a(Dependabot::Job::IgnoreCondition))
      expect(definition.existing_group_pull_requests)
        .to all(be_a(Dependabot::Job::ExistingGroupPullRequest))
      expect(definition.dependency_groups).to all(be_a(Dependabot::Job::DependencyGroupDefinition))
      expect(definition.blocked_versions).to all(be_a(Dependabot::Job::BlockedVersion))
      expect(definition.source).to be_a(Dependabot::Job::SourceDefinition)
      expect(definition.experiments).to eq("feature" => true, "timeout" => 60)
      expect(definition.commit_message_options).to eq("prefix" => "deps", "include-scope" => true)
    end

    context "with non-hash entries in tolerant collections" do
      let(:attributes) do
        super().merge(
          existing_group_pull_requests: [nil, { "dependency-group-name" => "group-a" }],
          dependency_groups: ["invalid", { "name" => "group-a" }],
          blocked_versions: [false, { "dependency-name" => "rake", "version-requirement" => "< 1" }]
        )
      end

      it "ignores them" do
        expect(definition.existing_group_pull_requests.length).to eq(1)
        expect(definition.dependency_groups.length).to eq(1)
        expect(definition.blocked_versions.length).to eq(1)
      end
    end

    context "with a malformed required scalar" do
      let(:attributes) { super().merge(package_manager: nil) }

      it "fails fast" do
        expect { definition }.to raise_error(TypeError, /package_manager/)
      end
    end
  end
end
