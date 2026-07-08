# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/branch_name_template"

RSpec.describe Dependabot::PullRequestCreator::BranchNameTemplate do
  describe ".validate_template" do
    context "with valid solo placeholders" do
      it "returns true" do
        expect(
          described_class.validate_template("{prefix}/{package_manager}/{dependency}-{version}", strategy: :solo)
        ).to be true
      end
    end

    context "with valid group placeholders" do
      it "returns true" do
        expect(
          described_class.validate_template("{prefix}/{package_manager}/{group_name}", strategy: :group)
        ).to be true
      end
    end

    context "with valid multi_ecosystem placeholders" do
      it "returns true" do
        expect(
          described_class.validate_template("{prefix}/{group_name}", strategy: :multi_ecosystem)
        ).to be true
      end
    end

    context "with an empty template" do
      it "raises an error" do
        expect do
          described_class.validate_template("", strategy: :solo)
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          "Template must be a non-empty string."
        )
      end
    end

    context "with unknown placeholders" do
      it "raises an error listing the unknown placeholders" do
        expect do
          described_class.validate_template("{prefix}/{foo}/{bar}", strategy: :solo)
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /Unknown placeholder\(s\): \{foo\}, \{bar\}/
        )
      end
    end

    context "with malformed braces" do
      it "raises an error about malformed braces" do
        expect do
          described_class.validate_template("{prefix}/{dependency", strategy: :solo)
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /Malformed or unclosed braces detected/
        )
      end
    end

    context "with {package_manager} in multi_ecosystem strategy" do
      it "raises an error" do
        expect do
          described_class.validate_template("{prefix}/{package_manager}/{group_name}", strategy: :multi_ecosystem)
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /\{package_manager\} is not available for multi-ecosystem groups/
        )
      end
    end

    context "with unknown strategy" do
      it "raises an error" do
        expect do
          described_class.validate_template("{prefix}", strategy: :unknown)
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /Unknown strategy: unknown/
        )
      end
    end

    context "with the {name} meta-placeholder" do
      it "is valid for all strategies" do
        expect(described_class.validate_template("{name}", strategy: :solo)).to be true
        expect(described_class.validate_template("{name}", strategy: :group)).to be true
        expect(described_class.validate_template("{name}", strategy: :multi_ecosystem)).to be true
      end
    end
  end

  describe ".validate_ref_name" do
    context "with a valid ref name" do
      it "returns true" do
        expect(described_class.validate_ref_name("dependabot/npm/lodash-4.17.21")).to be true
      end
    end

    context "with a ref containing control characters" do
      it "raises an error" do
        expect do
          described_class.validate_ref_name("branch\x00name")
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /is not a valid Git ref/
        )
      end
    end

    context "with a ref containing double dots" do
      it "raises an error" do
        expect do
          described_class.validate_ref_name("branch..name")
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /is not a valid Git ref/
        )
      end
    end

    context "with a ref starting with a dash" do
      it "raises an error" do
        expect do
          described_class.validate_ref_name("-branch")
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /is not a valid Git ref/
        )
      end
    end

    context "with a ref ending in .lock" do
      it "raises an error" do
        expect do
          described_class.validate_ref_name("branch.lock")
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /is not a valid Git ref/
        )
      end
    end

    context "with a ref containing double slashes" do
      it "raises an error" do
        expect do
          described_class.validate_ref_name("branch//name")
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /is not a valid Git ref/
        )
      end
    end
  end

  describe ".render" do
    context "with a solo strategy" do
      it "renders placeholders correctly" do
        result = described_class.render(
          "{prefix}/{package_manager}/{dependency}-{version}",
          {
            "prefix" => "dependabot",
            "package_manager" => "npm",
            "dependency" => "lodash",
            "version" => "4.17.21"
          },
          strategy: :solo
        )

        expect(result).to eq("dependabot/npm/lodash-4.17.21")
      end
    end

    context "with a group strategy" do
      it "renders placeholders and appends digest" do
        result = described_class.render(
          "{prefix}/{package_manager}/{group_name}",
          {
            "prefix" => "dependabot",
            "package_manager" => "npm",
            "group_name" => "frontend-deps"
          },
          strategy: :group,
          digest: "fc93691fd4"
        )

        expect(result).to eq("dependabot/npm/frontend-deps-fc93691fd4")
      end
    end

    context "with a multi_ecosystem strategy" do
      it "renders placeholders and appends digest" do
        result = described_class.render(
          "{prefix}/security/{group_name}",
          {
            "prefix" => "dependabot",
            "group_name" => "all-security"
          },
          strategy: :multi_ecosystem,
          digest: "7f8e9d0a1b"
        )

        expect(result).to eq("dependabot/security/all-security-7f8e9d0a1b")
      end
    end

    context "when a placeholder value is missing" do
      it "raises an error" do
        expect do
          described_class.render(
            "{prefix}/{package_manager}/{dependency}",
            { "prefix" => "dependabot", "package_manager" => "npm" },
            strategy: :solo
          )
        end.to raise_error(
          Dependabot::PullRequestCreator::BranchNameTemplate::Error,
          /Missing value for placeholder "\{dependency\}"/
        )
      end
    end

    context "with max_length truncation for solo" do
      it "truncates using SHA1 when branch exceeds max_length" do
        result = described_class.render(
          "{prefix}/{package_manager}/{dependency}-{version}",
          {
            "prefix" => "dependabot",
            "package_manager" => "npm_and_yarn",
            "dependency" => "very-long-dependency-name-that-will-exceed-the-limit",
            "version" => "1.0.0"
          },
          strategy: :solo,
          max_length: 50
        )

        expect(result.length).to be <= 50
      end
    end

    context "with max_length truncation for group (preserves digest)" do
      it "truncates while preserving the digest suffix" do
        result = described_class.render(
          "{prefix}/{package_manager}/{group_name}",
          {
            "prefix" => "dependabot",
            "package_manager" => "npm_and_yarn",
            "group_name" => "very-long-group-name-that-will-exceed-the-limit"
          },
          strategy: :group,
          digest: "fc93691fd4",
          max_length: 50
        )

        expect(result.length).to be <= 50
        expect(result).to end_with("-fc93691fd4")
      end
    end

    context "with solo strategy and no digest" do
      it "does not append a digest" do
        result = described_class.render(
          "{prefix}/{dependency}",
          { "prefix" => "deps", "dependency" => "lodash" },
          strategy: :solo,
          digest: "abc123"
        )

        expect(result).to eq("deps/lodash")
      end
    end

    context "with {name} meta-placeholder in solo" do
      it "renders the name value" do
        result = described_class.render(
          "{prefix}/{name}",
          { "prefix" => "dependabot", "name" => "lodash-4.17.21" },
          strategy: :solo
        )

        expect(result).to eq("dependabot/lodash-4.17.21")
      end
    end

    context "with target_branch placeholder" do
      it "renders the target branch" do
        result = described_class.render(
          "{prefix}/{target_branch}/{dependency}",
          {
            "prefix" => "dependabot",
            "target_branch" => "develop",
            "dependency" => "lodash"
          },
          strategy: :solo
        )

        expect(result).to eq("dependabot/develop/lodash")
      end
    end
  end
end
