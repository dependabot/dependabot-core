# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request"

RSpec.describe Dependabot::PullRequest do
  context "when there are different formats from the job" do
    let(:existing_pull_requests) do
      [[{ "dependency-name" => "foo", "dependency-version" => "1.0.0", "directory" => "/", "pr-number" => 123 }]]
    end

    it "can properly handle when each PR from the job is an array" do
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

    it "can properly handle when each PR is a hash and dependencies object is present" do
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

    it "treats '/.' and '/' directories as equivalent" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/."
          )
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/"
          )
        ]
      )

      expect(pr1).to eq(pr2)
    end

    it "normalizes directories" do
      pr1 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "hello/world/"
          )
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/hello/world"
          )
        ]
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

    it "is false when one has directory and the other doesn't" do
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
            version: "1.0.0"
          )
        ],
        pr_number: 456
      )

      expect(pr1).not_to eq(pr2)
    end

    it "is false when directories are different" do
      existing_pr = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "rollup",
            version: "2.79.2",
            directory: "/packages/corelib"
          )
        ],
        pr_number: 123
      )
      new_pr = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "rollup",
            version: "2.79.2",
            directory: "/"
          )
        ]
      )

      expect(existing_pr).not_to eq(new_pr)
    end

    it "is false when comparing PRs from job definition with different directories" do
      existing_prs = described_class.create_from_job_definition(
        existing_pull_requests: [
          [{ "dependency-name" => "rollup", "dependency-version" => "2.79.2", "directory" => "/packages/corelib" }]
        ]
      )

      updated_dependency = instance_double(
        Dependabot::Dependency,
        name: "rollup",
        version: "2.79.2",
        removed?: false,
        directory: "/."
      )
      new_pr = described_class.create_from_updated_dependencies([updated_dependency])

      expect(existing_prs.find { |pr| pr == new_pr }).to be_nil
    end

    it "is false when existing PR has no directory but new PR does" do
      existing_prs = described_class.create_from_job_definition(
        existing_pull_requests: [
          [{ "dependency-name" => "rollup", "dependency-version" => "2.79.2" }]
        ]
      )

      updated_dependency = instance_double(
        Dependabot::Dependency,
        name: "rollup",
        version: "2.79.2",
        removed?: false,
        directory: "/."
      )
      new_pr = described_class.create_from_updated_dependencies([updated_dependency])

      expect(existing_prs.first.using_directory?).to be false
      expect(new_pr.using_directory?).to be true
      expect(existing_prs.find { |pr| pr == new_pr }).to be_nil
    end
  end
end
