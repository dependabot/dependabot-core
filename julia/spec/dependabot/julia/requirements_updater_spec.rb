# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/update_checker/requirements_updater"
require "dependabot/julia/version"

RSpec.describe Dependabot::Julia::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      target_version: target_version,
      update_strategy: :bump_versions
    )
  end

  let(:requirements) do
    [{
      requirement: requirement_string,
      file: "Project.toml",
      groups: ["dependencies"],
      source: nil
    }]
  end

  describe "#updated_requirements" do
    subject(:result) { updater.updated_requirements.first[:requirement] }

    # Test cases: [requirement, target_version, expected_result]
    {
      "keeps requirement when satisfied" => [
        ["0.34.6", "0.34.7", "0.34.6"],
        ["^0.34.6", "0.34.7", "^0.34.6"],
        ["~0.34.6", "0.34.7", "~0.34.6"],
        ["1.2.3", "1.3.0", "1.2.3"]
      ],
      "appends simplified spec when unsatisfied (defaults to space after comma)" => [
        ["0.34.6", "0.35.0", "0.34.6, 0.35"],
        ["0.34.6", "1.0.0", "0.34.6, 1.0"],
        ["0.0.5", "0.0.8", "0.0.5, 0.0.8"],
        ["1.2.3", "2.0.0", "1.2.3, 2.0"]
      ],
      "appends plain spec regardless of prefix (defaults to space after comma)" => [
        ["^0.34.6", "0.35.0", "^0.34.6, 0.35"],
        ["^1.2.3", "2.0.0", "^1.2.3, 2.0"],
        ["~0.34.6", "0.35.0", "~0.34.6, 0.35"]
      ],
      "preserves spacing format when appending" => [
        ["0.6,0.7,0.8", "0.9.0", "0.6,0.7,0.8,0.9"],
        ["0.6, 0.7, 0.8", "0.9.0", "0.6, 0.7, 0.8, 0.9"],
        ["1.2,1.3", "2.0.0", "1.2,1.3,2.0"],
        ["1.2, 1.3", "2.0.0", "1.2, 1.3, 2.0"]
      ],
      "does not append when target is already included in existing range (issue #13938)" => [
        # Major-only version covers all minor/patch within that major
        ["2", "2.6.0", "2"],
        ["2", "2.99.99", "2"],
        # Mixed caret and plain versions - target is covered by plain major version
        ["^1.10, 2", "2.6.0", "^1.10, 2"],
        # Multiple caret specs with major version - target covered by '1'
        ["^0.20, ^0.21, 1", "1.3.0", "^0.20, ^0.21, 1"],
        # Target version exactly at the range boundary (still included)
        ["1", "1.0.0", "1"],
        # Caret spec covering the target
        ["^2.0", "2.6.0", "^2.0"]
      ]
    }.each do |description, test_cases|
      context "when #{description}" do
        test_cases.each do |req, target, expected|
          context "with #{req} and target #{target}" do
            let(:requirement_string) { req }
            let(:target_version) { target }

            it { is_expected.to eq(expected) }
          end
        end
      end
    end

    context "with special cases" do
      context "with nil requirement (no compat entry)" do
        let(:requirements) { [{ requirement: nil, file: "Project.toml", groups: ["dependencies"], source: nil }] }
        let(:target_version) { "0.35.0" }

        it { is_expected.to eq("0.35.0") }
      end

      context "with range requirement" do
        let(:requirement_string) { "0.34-0.35" }
        let(:target_version) { "0.36.0" }

        it "keeps range unchanged" do
          expect(result).to eq("0.34-0.35")
        end
      end
    end
  end
end
