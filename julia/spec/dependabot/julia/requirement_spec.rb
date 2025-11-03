# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/requirement"
require "dependabot/julia/version"

RSpec.describe Dependabot::Julia::Requirement do
  describe ".requirements_array" do
    subject(:requirement) { described_class.requirements_array(requirement_string).first }

    let(:satisfied_versions) { versions.select { |v| requirement.satisfied_by?(Dependabot::Julia::Version.new(v)) } }
    let(:unsatisfied_versions) { versions.reject { |v| requirement.satisfied_by?(Dependabot::Julia::Version.new(v)) } }

    shared_examples "version satisfaction" do |req_string, satisfied, unsatisfied|
      context "with #{req_string}" do
        let(:requirement_string) { req_string }
        let(:versions) { satisfied + unsatisfied }

        it "satisfies expected versions" do
          expect(satisfied_versions).to match_array(satisfied)
        end

        it "does not satisfy other versions" do
          expect(unsatisfied_versions).to match_array(unsatisfied)
        end
      end
    end

    context "with implicit caret semantics" do
      it_behaves_like "version satisfaction", "0.34.6", ["0.34.7", "0.34.10"], ["0.35.0", "0.33.9"]
      it_behaves_like "version satisfaction", "1.5.3", ["1.5.4", "1.6.0", "1.9.9"], ["2.0.0", "1.4.9"]
      # For 0.0.x versions, Julia's caret semantics are [0.0.x, 0.0.x+1), so 0.0.5 only matches 0.0.5 itself
      it_behaves_like "version satisfaction", "0.0.5", ["0.0.5"], ["0.0.6", "0.0.9", "0.1.0", "0.0.4"]
    end

    context "with explicit constraints" do
      it_behaves_like "version satisfaction", "^0.34.6", ["0.34.7"], ["0.35.0"]
      it_behaves_like "version satisfaction", "~0.34.6", ["0.34.7"], ["0.35.0"]
    end

    context "with special constraints" do
      context "with wildcard" do
        let(:requirement_string) { "*" }

        it "allows any version" do
          expect(requirement.satisfied_by?(Dependabot::Julia::Version.new("0.1.0"))).to be true
          expect(requirement.satisfied_by?(Dependabot::Julia::Version.new("999.0.0"))).to be true
        end
      end

      context "with nil" do
        let(:requirement_string) { nil }

        it "allows any version" do
          expect(requirement.satisfied_by?(Dependabot::Julia::Version.new("0.1.0"))).to be true
        end
      end
    end

    context "with multiple constraints" do
      let(:requirement_string) { "0.34, 0.35" }

      it "creates multiple requirements" do
        requirements = described_class.requirements_array(requirement_string)
        expect(requirements.length).to eq(2)

        # At least one requirement should satisfy each version in its range
        expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("0.34.5")) }).to be true
        expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("0.35.1")) }).to be true
      end
    end
  end

  describe ".normalize_julia_constraint" do
    subject(:normalized) { described_class.send(:normalize_julia_constraint, constraint) }

    {
      "0.34.6" => [">= 0.34.6", "< 0.35.0"],
      "^0.34.6" => [">= 0.34.6", "< 0.35.0"],
      "~0.34.6" => [">= 0.34.6", "< 0.35.0"],
      ">= 0.34.6" => [">= 0.34.6"]
    }.each do |input, expected|
      context "with #{input}" do
        let(:constraint) { input }

        it { is_expected.to eq(expected) }
      end
    end
  end
end
