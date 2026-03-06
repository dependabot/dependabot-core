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

    # Test cases from Julia Pkg documentation: https://pkgdocs.julialang.org/v1/compatibility/
    context "with caret specifiers (Julia docs)" do
      # ^1.2.3 -> [1.2.3, 2.0.0), ^1.2 -> [1.2.0, 2.0.0), ^1 -> [1.0.0, 2.0.0)
      it_behaves_like "version satisfaction", "^1.2.3", ["1.2.3", "1.5.0", "1.99.0"], ["2.0.0", "1.2.2"]
      it_behaves_like "version satisfaction", "^1.2", ["1.2.0", "1.9.0"], ["2.0.0", "1.1.9"]
      it_behaves_like "version satisfaction", "^1", ["1.0.0", "1.99.0"], ["2.0.0", "0.9.9"]

      # ^0.2.3 -> [0.2.3, 0.3.0)
      it_behaves_like "version satisfaction", "^0.2.3", ["0.2.3", "0.2.9"], ["0.3.0", "0.2.2"]

      # ^0.0.3 -> [0.0.3, 0.0.4)
      it_behaves_like "version satisfaction", "^0.0.3", ["0.0.3"], ["0.0.4", "0.0.2", "0.1.0"]

      # ^0.0 -> [0.0.0, 0.1.0)
      it_behaves_like "version satisfaction", "^0.0", ["0.0.0", "0.0.5", "0.0.99"], ["0.1.0"]

      # ^0 -> [0.0.0, 1.0.0)
      it_behaves_like "version satisfaction", "^0", ["0.0.0", "0.9.0", "0.99.99"], ["1.0.0"]
    end

    context "with tilde specifiers (Julia docs)" do
      # ~1.2.3 -> [1.2.3, 1.3.0), ~1.2 -> [1.2.0, 1.3.0)
      it_behaves_like "version satisfaction", "~1.2.3", ["1.2.3", "1.2.9"], ["1.3.0", "1.2.2"]
      it_behaves_like "version satisfaction", "~1.2", ["1.2.0", "1.2.9"], ["1.3.0", "1.1.9"]

      # ~1 -> [1.0.0, 2.0.0) - equivalent to ^1
      it_behaves_like "version satisfaction", "~1", ["1.0.0", "1.99.0"], ["2.0.0", "0.9.9"]

      # ~0.2.3 -> [0.2.3, 0.3.0)
      it_behaves_like "version satisfaction", "~0.2.3", ["0.2.3", "0.2.9"], ["0.3.0", "0.2.2"]

      # ~0.0.3 -> [0.0.3, 0.0.4) - same as caret for 0.0.x
      it_behaves_like "version satisfaction", "~0.0.3", ["0.0.3"], ["0.0.4", "0.0.2"]

      # ~0.0 -> [0.0.0, 0.1.0)
      it_behaves_like "version satisfaction", "~0.0", ["0.0.0", "0.0.5"], ["0.1.0"]

      # ~0 -> [0.0.0, 1.0.0) - equivalent to ^0
      it_behaves_like "version satisfaction", "~0", ["0.0.0", "0.9.0"], ["1.0.0"]
    end

    context "with implicit caret semantics (plain versions)" do
      # Plain versions use implicit caret: "1.2.3" == "^1.2.3"
      it_behaves_like "version satisfaction", "0.34.6", ["0.34.7", "0.34.10"], ["0.35.0", "0.33.9"]
      it_behaves_like "version satisfaction", "1.5.3", ["1.5.4", "1.6.0", "1.9.9"], ["2.0.0", "1.4.9"]
      it_behaves_like "version satisfaction", "0.0.5", ["0.0.5"], ["0.0.6", "0.0.9", "0.1.0", "0.0.4"]

      # Major-only version: "2" == "^2" -> [2.0.0, 3.0.0)
      it_behaves_like "version satisfaction", "2", ["2.0.0", "2.6.0", "2.99.99"], ["3.0.0", "1.9.9"]
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

    # Union of version specifiers (Julia docs): comma-separated specs form OR conditions
    context "with union of specifiers (Julia docs)" do
      context "with '1.2, 2' (results in [1.2.0, 3.0.0) per docs)" do
        let(:requirement_string) { "1.2, 2" }

        it "creates separate requirements for each spec" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.length).to eq(2)
        end

        it "satisfies versions in either range" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("1.5.0")) }).to be true
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("2.5.0")) }).to be true
        end

        it "does not satisfy version 3.0.0" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("3.0.0")) }).to be false
        end
      end

      context "with '0.2, 1' (results in [0.2.0, 0.3.0) ∪ [1.0.0, 2.0.0) per docs)" do
        let(:requirement_string) { "0.2, 1" }

        it "satisfies versions in either disjoint range" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("0.2.5")) }).to be true
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("1.5.0")) }).to be true
        end

        it "does not satisfy versions between the ranges" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("0.5.0")) }).to be false
        end
      end
    end

    # Issue #13938: Compat change was already included in range
    context "with mixed specifiers (issue #13938)" do
      context "with '^1.10, 2'" do
        let(:requirement_string) { "^1.10, 2" }

        it "creates separate requirements (not a compound AND constraint)" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.length).to eq(2)
        end

        it "satisfies version 2.6 via the '2' constraint" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("2.6.0")) }).to be true
        end

        it "satisfies version 1.10.5 via the '^1.10' constraint" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("1.10.5")) }).to be true
        end

        it "does not satisfy version 3.0.0 (outside all ranges)" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("3.0.0")) }).to be false
        end
      end

      context "with '^0.20, ^0.21, 1'" do
        let(:requirement_string) { "^0.20, ^0.21, 1" }

        it "creates three separate requirements" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.length).to eq(3)
        end

        it "satisfies version 1.3 via the '1' constraint" do
          requirements = described_class.requirements_array(requirement_string)
          expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("1.3.0")) }).to be true
        end
      end
    end

    context "with compound comparison operators (AND conditions)" do
      let(:requirement_string) { ">= 1.0, < 2.0" }

      it "creates a single compound requirement" do
        requirements = described_class.requirements_array(requirement_string)
        expect(requirements.length).to eq(1)
      end

      it "satisfies version 1.5.0" do
        requirements = described_class.requirements_array(requirement_string)
        expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("1.5.0")) }).to be true
      end

      it "does not satisfy version 2.5.0" do
        requirements = described_class.requirements_array(requirement_string)
        expect(requirements.any? { |r| r.satisfied_by?(Dependabot::Julia::Version.new("2.5.0")) }).to be false
      end
    end
  end

  describe ".normalize_julia_constraint" do
    subject(:normalized) { described_class.send(:normalize_julia_constraint, constraint) }

    # Test normalization output matches Julia docs expectations
    {
      # Implicit caret (plain versions)
      "1.2.3" => [">= 1.2.3", "< 2.0.0"],
      "0.34.6" => [">= 0.34.6", "< 0.35.0"],
      "0.0.5" => [">= 0.0.5", "< 0.0.6"],

      # Explicit caret
      "^1.2.3" => [">= 1.2.3", "< 2.0.0"],
      "^0.34.6" => [">= 0.34.6", "< 0.35.0"],
      "^0.0.3" => [">= 0.0.3", "< 0.0.4"],
      "^0.0" => [">= 0.0", "< 0.1.0"],
      "^0" => [">= 0", "< 1.0.0"],

      # Tilde
      "~1.2.3" => [">= 1.2.3", "< 1.3.0"],
      "~0.34.6" => [">= 0.34.6", "< 0.35.0"],
      "~1" => [">= 1", "< 2.0.0"],

      # Pass-through for comparison operators
      ">= 0.34.6" => [">= 0.34.6"]
    }.each do |input, expected|
      context "with #{input}" do
        let(:constraint) { input }

        it { is_expected.to eq(expected) }
      end
    end
  end
end
