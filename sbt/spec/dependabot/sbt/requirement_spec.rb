# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/requirement"
require "dependabot/sbt/version"

RSpec.describe Dependabot::Sbt::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject(:requirement) { described_class.new(requirement_string) }

    context "with an exact version (typical SBT usage)" do
      let(:requirement_string) { "1.0.0" }

      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
    end

    context "with a pre-release version" do
      let(:requirement_string) { "1.3.alpha" }

      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.alpha")) }
    end

    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0")) }

      context "when needing a > operator" do
        let(:requirement_string) { "(1.0.0,)" }

        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0")) }
      end

      context "when needing a > and a < operator" do
        let(:requirement_string) { "(1.0.0, 2.0.0)" }

        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0", "< 2.0.0")) }
      end

      context "when needing a >= and a <= operator" do
        let(:requirement_string) { "[1.0.0, 2.0.0]" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 2.0.0")) }
      end
    end

    context "with a soft requirement" do
      let(:requirement_string) { "[1.0.0]" }

      it "treats it as an equality matcher" do
        expect(requirement).to be_satisfied_by(
          Dependabot::Sbt::Version.new("1.0.0")
        )
      end
    end
  end

  describe ".requirements_array" do
    subject(:requirements) { described_class.requirements_array(requirement_string) }

    context "with a single requirement" do
      let(:requirement_string) { "1.0.0" }

      it "returns an array with one requirement" do
        expect(requirements.length).to eq(1)
      end
    end

    context "with multiple OR requirements" do
      let(:requirement_string) { "[1.0,2.0),(3.0,4.0)" }

      it "returns an array with multiple requirements" do
        expect(requirements.length).to eq(2)
      end
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement_string) { ">=1.0.0" }

    context "with a version that satisfies the requirement" do
      let(:version) { Dependabot::Sbt::Version.new("1.5.0") }

      it { is_expected.to be(true) }
    end

    context "with a version that does not satisfy the requirement" do
      let(:version) { Dependabot::Sbt::Version.new("0.9.0") }

      it { is_expected.to be(false) }
    end
  end
end
