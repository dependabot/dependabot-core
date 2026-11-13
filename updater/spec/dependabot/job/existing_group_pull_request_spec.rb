# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/existing_group_pull_request"

RSpec.describe Dependabot::Job::ExistingGroupPullRequest do
  describe ".from_hash" do
    it "parses an existing group pull request" do
      pull_request = described_class.from_hash(
        {
          "dependency-group-name" => "production",
          "pr_number" => 123,
          "dependencies" => [
            {
              "dependency-name" => "rails",
              "dependency-version" => "7.0.8",
              "directory" => "/app",
              "dependency-removed" => true
            }
          ]
        }
      )

      expect(pull_request).to have_attributes(
        dependency_group_name: "production",
        pr_number: 123
      )
      expect(pull_request.dependencies).to contain_exactly(
        have_attributes(
          name: "rails",
          version: "7.0.8",
          directory: "/app",
          removed: true
        )
      )
    end

    it "drops malformed scalars and filters non-hash dependencies" do
      pull_request = described_class.from_hash(
        {
          "dependency-group-name" => 1,
          "pr_number" => "123",
          "dependencies" => [
            nil,
            {
              "dependency-name" => 2,
              "dependency-version" => [],
              "directory" => false,
              "dependency-removed" => "true"
            }
          ]
        }
      )

      expect(pull_request).to have_attributes(
        dependency_group_name: nil,
        pr_number: nil
      )
      expect(pull_request.dependencies).to contain_exactly(
        have_attributes(name: nil, version: nil, directory: nil, removed: false)
      )
    end

    it "drops malformed dependencies containers" do
      pull_request = described_class.from_hash("dependencies" => "rails")

      expect(pull_request.dependencies).to be_nil
    end
  end
end
