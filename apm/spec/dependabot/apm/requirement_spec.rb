# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/apm/requirement"

RSpec.describe Dependabot::Apm::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">= 1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { "~> 1.2.0, >= 1.2.3" }

      it "splits the requirement on the comma" do
        expect(requirement).to eq(described_class.new("~> 1.2.0", ">= 1.2.3"))
      end
    end
  end

  describe ".requirements_array" do
    subject { described_class.requirements_array(requirement_string) }

    let(:requirement_string) { ">= 1.0.0" }

    it "returns a single-element array" do
      expect(described_class.requirements_array(requirement_string))
        .to eq([described_class.new(">= 1.0.0")])
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement_string) { ">= 1.0.0" }

    context "when the version satisfies the requirement" do
      let(:version) { Dependabot::Apm::Version.new("1.2.0") }

      it { is_expected.to be(true) }
    end

    context "when the version does not satisfy the requirement" do
      let(:version) { Dependabot::Apm::Version.new("0.9.0") }

      it { is_expected.to be(false) }
    end

    context "with a prerelease upper bound" do
      let(:requirement_string) { "< 1.0.0-alpha.beta" }

      # SemVer orders numeric prerelease identifiers below alphanumeric ones,
      # so 1.0.0-alpha.1 < 1.0.0-alpha.beta. RubyGems orders them the other way,
      # which this ecosystem must not inherit.
      context "with a lower prerelease under SemVer precedence" do
        let(:version) { Dependabot::Apm::Version.new("1.0.0-alpha.1") }

        it { is_expected.to be(true) }
      end

      context "with a higher prerelease under SemVer precedence" do
        let(:version) { Dependabot::Apm::Version.new("1.0.0-alpha.gamma") }

        it { is_expected.to be(false) }
      end
    end

    context "with a prerelease range" do
      let(:requirement_string) { ">= 1.0.0-alpha, < 1.0.0" }

      context "when the version is within the prerelease range" do
        let(:version) { Dependabot::Apm::Version.new("1.0.0-alpha.5") }

        it { is_expected.to be(true) }
      end

      context "when the version is the final release" do
        let(:version) { Dependabot::Apm::Version.new("1.0.0") }

        it { is_expected.to be(false) }
      end
    end

    context "with a partial (non-SemVer) bound" do
      let(:requirement_string) { ">= 1.0" }

      let(:version) { Dependabot::Apm::Version.new("1.5.0") }

      it { is_expected.to be(true) }
    end

    context "with a pessimistic (~>) constraint on a strict SemVer operand" do
      let(:requirement_string) { "~> 1.2.3" }

      # Gem::Requirement evaluates `~>` via the operand's `bump`; the inherited
      # Gem::Version#bump would build the partial `1.3` that Apm::Version rejects,
      # so this must not raise and must bound the range at the next minor.
      context "when the version is within the bound" do
        let(:version) { Dependabot::Apm::Version.new("1.2.9") }

        it { is_expected.to be(true) }
      end

      context "when the version is below the lower bound" do
        let(:version) { Dependabot::Apm::Version.new("1.2.2") }

        it { is_expected.to be(false) }
      end

      context "when the version reaches the next minor" do
        let(:version) { Dependabot::Apm::Version.new("1.3.0") }

        it { is_expected.to be(false) }
      end
    end
  end

  describe ".parse" do
    context "with a strict SemVer prerelease bound" do
      it "builds an Apm::Version operand so ordering stays SemVer-aware" do
        op, version = described_class.parse("< 1.0.0-alpha.beta")

        expect(op).to eq("<")
        expect(version).to be_a(Dependabot::Apm::Version)
        expect(version.to_s).to eq("1.0.0-alpha.beta")
      end
    end

    context "with a partial bound" do
      it "falls back to a plain Gem::Version operand" do
        op, version = described_class.parse(">= 1.0")

        expect(op).to eq(">=")
        expect(version).to be_a(Gem::Version)
        expect(version).not_to be_a(Dependabot::Apm::Version)
      end
    end
  end
end
