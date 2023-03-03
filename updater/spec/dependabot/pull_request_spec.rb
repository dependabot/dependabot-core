# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request"

RSpec.describe Dependabot::PullRequest do
  describe "==" do
    it "is true when all the dependencies are the same" do
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
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "bar",
            version: "1.0.0"
          )
        ]
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
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "2.0.0"
          )
        ]
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
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            removed: true
          )
        ]
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
        ]
      )
      pr2 = described_class.new(
        [
          Dependabot::PullRequest::Dependency.new(
            name: "foo",
            version: "1.0.0",
            directory: "/bar"
          )
        ]
      )

      expect(pr1).not_to eq(pr2)
    end
  end
end
