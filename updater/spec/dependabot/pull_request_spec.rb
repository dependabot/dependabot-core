# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request"

RSpec.describe Dependabot::PullRequest do
  context "when there are different formats from the job" do
    let(:existing_pull_requests) do
      [[{ "dependency-name" => "foo", "dependency-version" => "1.0.0", "directory" => "/", "pr-number" => 123 }]]
    end
    it "it can properly handle when each PR from the job is an array" do
      pr2 = described_class.create_from_job_definition( # ← Fix: Correct method call
        existing_pull_requests: existing_pull_requests
      )
      pr2 = pr2.first # get the first PR from the array

      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/"
          )
        ],
        pr_number: 123
      )
      expect(pr2.pr_number).to eq(123)
      expect(pr2).to eq(pr1)
    end
    it "it can properly handle when each PR is a hash and dependencies object is present" do
      existing_pull_requests =
        [{ "pr-number" => 123,
           "dependencies" => [{ "dependency-name" => "foo", "dependency-version" => "1.0.0", "directory" => "/" },
                              { "dependency-name" => "bar", "dependency-version" => "2.0.0", "directory" => "/bar" }] }]

      pr2 = described_class.create_from_job_definition(
        existing_pull_requests: existing_pull_requests
      )
      pr2 = pr2.first # get the first PR from the array returned

      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/"
          ),
          Dependabot::PullRequest::Dependency.new( # ← Add second dependency
            name: "bar",
            version: "2.0.0",
            directory: "/bar"
          )
        ],
        pr_number: 123
      )

      expect(pr2).to eq(pr1)
    end
  end

  describe "==" do
    it "is true when all the dependencies are the same, excluding pr_number" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )

      expect(pr1).to eq(pr2)
    end

    it "is false when the name is different" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "bar",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when the version is different" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "2.0.0"
          )
        ],
        pr_number: 123
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when the dependency is removed" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            removed: true
          )
        ],
        pr_number: 123
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when the directory is different" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/foo"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/bar"
          )
        ],
        pr_number: 123
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when the left has more dependencies" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          ),
          Dependabot::PullRequest::Dependency.new(
            name: "bar",
            version: "2.0.0"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when the right has more dependencies" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          )
        ],
        pr_number: 123
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0"
          ),
          Dependabot::PullRequest::Dependency.new(
            name: "bar",
            version: "2.0.0"
          )
        ],
        pr_number: 456
      )

      expect(pr1).not_to eq(pr2)
    end
  end
end
