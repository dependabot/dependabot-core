# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/requirement"
require "dependabot/rust_toolchain/version"

RSpec.describe Dependabot::RustToolchain::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.72.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { ">= 1.72, < 1.73" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.72", "< 1.73")) }
    end
  end

  describe "#satisfied_by?" do
    context "with version channel types" do
      let(:requirement_string) { ">= 1.72.0" }

      it "is satisfied by newer version" do
        expect(requirement.satisfied_by?("1.73.0")).to be true
      end

      it "is satisfied by equal version" do
        expect(requirement.satisfied_by?("1.72.0")).to be true
      end

      it "is not satisfied by older version" do
        expect(requirement.satisfied_by?("1.71.0")).to be false
      end
    end

    context "with date channel types" do
      let(:requirement_string) { ">= nightly-2023-10-01" }

      it "is satisfied by newer date in same channel" do
        expect(requirement.satisfied_by?("nightly-2023-10-02")).to be true
      end

      it "is satisfied by equal date" do
        expect(requirement.satisfied_by?("nightly-2023-10-01")).to be true
      end

      it "is not satisfied by older date in same channel" do
        expect(requirement.satisfied_by?("nightly-2023-09-30")).to be false
      end

      it "is not satisfied by different channel even if date is newer" do
        expect(requirement.satisfied_by?("beta-2023-10-02")).to be false
      end
    end

    context "with stability channel types" do
      let(:requirement_string) { ">= beta" }

      it "is satisfied by higher stability" do
        expect(requirement.satisfied_by?("stable")).to be true
      end

      it "is satisfied by equal stability" do
        expect(requirement.satisfied_by?("beta")).to be true
      end

      it "is not satisfied by lower stability" do
        expect(requirement.satisfied_by?("nightly")).to be false
      end
    end

    context "with exact requirements" do
      let(:requirement_string) { "= nightly-2023-10-01" }

      it "is satisfied by exact match" do
        expect(requirement.satisfied_by?("nightly-2023-10-01")).to be true
      end

      it "is not satisfied by different date" do
        expect(requirement.satisfied_by?("nightly-2023-10-02")).to be false
      end

      it "is not satisfied by different channel" do
        expect(requirement.satisfied_by?("beta-2023-10-01")).to be false
      end
    end

    context "with mixed channel types" do
      it "cannot compare version with date channel" do
        requirement = described_class.new(">= 1.72.0")
        expect(requirement.satisfied_by?("nightly-2023-10-01")).to be false
      end

      it "cannot compare stability with date channel" do
        requirement = described_class.new(">= stable")
        expect(requirement.satisfied_by?("nightly-2023-10-01")).to be false
      end
    end
  end

  describe ".parse" do
    it "parses version strings correctly" do
      op, version = described_class.parse("1.72.0")
      expect(op).to eq("=")
      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("1.72.0")
    end

    it "parses date channel strings correctly" do
      op, version = described_class.parse("nightly-2023-10-01")
      expect(op).to eq("=")
      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("nightly-2023-10-01")
    end

    it "parses stability channel strings correctly" do
      op, version = described_class.parse("stable")
      expect(op).to eq("=")
      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("stable")
    end

    it "raises error for invalid formats" do
      expect { described_class.parse("invalid-format") }.to raise_error(Gem::Requirement::BadRequirementError)
    end
  end
end
