# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit"

RSpec.describe Dependabot::PreCommit do
  describe "humanized_previous_version_builder registration" do
    subject(:humanized_previous_version) { dependency.humanized_previous_version }

    context "when previous_requirements contain a comment with version (frozen SHA format)" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/tofuutils/pre-commit-opentofu",
          version: "10864545ddc58bd96330029b6bff16da3d072237",
          previous_version: "04bfdda8eb902a604850282feec57563f388d71e",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/tofuutils/pre-commit-opentofu",
              ref: "10864545ddc58bd96330029b6bff16da3d072237",
              branch: nil
            },
            metadata: { comment_version: "v2.2.1", new_comment_version: "v2.2.2" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/tofuutils/pre-commit-opentofu",
              ref: "04bfdda8eb902a604850282feec57563f388d71e",
              branch: nil
            },
            metadata: { comment: "# v2.2.1" }
          }],
          package_manager: "pre_commit"
        )
      end

      it "returns the version from the comment instead of the SHA" do
        expect(humanized_previous_version).to eq("v2.2.1")
      end
    end

    context "when previous_requirements contain a frozen comment format" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/example/hooks",
          version: "abcdef1234567890abcdef1234567890abcdef12",
          previous_version: "1234567890abcdef1234567890abcdef12345678",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/example/hooks",
              ref: "abcdef1234567890abcdef1234567890abcdef12",
              branch: nil
            },
            metadata: { comment_version: "7.3.0", new_comment_version: "8.0.0" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/example/hooks",
              ref: "1234567890abcdef1234567890abcdef12345678",
              branch: nil
            },
            metadata: { comment: "# frozen: 7.3.0" }
          }],
          package_manager: "pre_commit"
        )
      end

      it "returns the version from the frozen comment" do
        expect(humanized_previous_version).to eq("7.3.0")
      end
    end

    context "when previous_requirements have no comment (tag-based version)" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/pre-commit/pre-commit-hooks",
          version: "v4.5.0",
          previous_version: "v4.4.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "v4.5.0",
              branch: nil
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "v4.4.0",
              branch: nil
            }
          }],
          package_manager: "pre_commit"
        )
      end

      it "falls back to the previous_version" do
        expect(humanized_previous_version).to eq("v4.4.0")
      end
    end

    context "when comment does not match version pattern" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/example/hooks",
          version: "abcdef1234567890abcdef1234567890abcdef12",
          previous_version: "1234567890abcdef1234567890abcdef12345678",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/example/hooks",
              ref: "abcdef1234567890abcdef1234567890abcdef12",
              branch: nil
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: {
              type: "git",
              url: "https://github.com/example/hooks",
              ref: "1234567890abcdef1234567890abcdef12345678",
              branch: nil
            },
            metadata: { comment: "# some random comment" }
          }],
          package_manager: "pre_commit"
        )
      end

      it "falls back to previous_ref (SHA in this case)" do
        # When ref_changed? is true and previous_ref exists, it returns previous_ref
        expect(humanized_previous_version).to eq("1234567890abcdef1234567890abcdef12345678")
      end
    end
  end
end
