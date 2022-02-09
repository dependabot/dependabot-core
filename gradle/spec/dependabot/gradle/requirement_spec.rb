# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/requirement"
require "dependabot/gradle/version"

RSpec.describe Dependabot::Gradle::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject(:requirement) { described_class.new(requirement_string) }

    context "with a pre-release version" do
      let(:requirement_string) { "1.3.alpha" }
      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.a")) }
    end

    context "with a version that wouldn't be a valid Gem::Version" do
      let(:requirement_string) { ">= Finchley.SR3" }

      it "creates a requirement object" do
        expect(requirement).to be_satisfied_by(
          Dependabot::Gradle::Version.new("Finchley.SR4")
        )
      end
    end

    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }
      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0")) }

      context "which needs a > operator" do
        let(:requirement_string) { "(1.0.0,)" }
        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0")) }
      end

      context "which needs a > and a < operator" do
        let(:requirement_string) { "(1.0.0, 2.0.0)" }
        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0", "< 2.0.0")) }
      end

      context "which needs a >= and a <= operator" do
        let(:requirement_string) { "[ 1.0.0,2.0.0 ]" }
        it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 2.0.0")) }
      end
    end

    context "with a soft requirement" do
      let(:requirement_string) { "1.0.0" }
      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
    end

    context "with a dynamic version requirement" do
      let(:requirement_string) { "1.+" }
      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }

      context "that specifies a minimum" do
        let(:requirement_string) { "1.5+" }
        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5").to_s) }
      end

      context "that is just a +" do
        let(:requirement_string) { "+" }
        its(:to_s) { is_expected.to eq(Gem::Requirement.new(">= 0").to_s) }
      end

      context "with a comma-separated dynamic version requirements" do
        let(:requirement_string) { "1.+, 2.+" }
        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0", "~> 2.0").to_s) }
      end
    end

    context "with a hard requirement" do
      let(:requirement_string) { "[1.0.0]" }
      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
    end

    context "with a comma-separated ruby style version requirement" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }
      it { is_expected.to eq(described_class.new("~> 4.2.5", ">= 4.2.5.1")) }
    end
  end

  describe ".requirements_array" do
    subject(:array) { described_class.requirements_array(requirement_string) }

    context "with exact requirement" do
      let(:requirement_string) { "1.0.0" }
      it { is_expected.to eq([described_class.new("= 1.0.0")]) }
    end

    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }
      it { is_expected.to eq([described_class.new(">= 1.0.0")]) }
    end

    context "with two range requirements" do
      let(:requirement_string) { "(,1.0.0),(1.0.0,)" }
      it "builds the correct array of requirements" do
        expect(array).to match_array(
          [
            described_class.new("> 1.0.0"),
            described_class.new("< 1.0.0")
          ]
        )
      end
    end

    context "with a comma-separated ruby style version requirement" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }
      it { is_expected.to eq([described_class.new("~> 4.2.5", ">= 4.2.5.1")]) }
    end

    context "with a comma-separated ruby style requirement with gradle versions" do
      let(:requirement_string) { ">= Finchley.a, < Finchley.999999" }
      it { is_expected.to eq([described_class.new(">= Finchley.a", "< Finchley.999999")]) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "for the current version" do
        let(:version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(true) }

        context "when the requirement includes a post-release" do
          let(:requirement_string) { ">=1.0.0u2" }
          it { is_expected.to eq(false) }
        end
      end

      context "for an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(false) }
      end
    end

    context "with a Gradle::Version" do
      let(:version) do
        Dependabot::Gradle::Version.new(version_string)
      end

      context "for the current version" do
        let(:version_string) { "1.0.0" }
        it { is_expected.to eq(true) }

        context "for a post-release version" do
          let(:version_string) { "1.0.0u2" }
          it { is_expected.to eq(true) }
        end

        context "for a pre-release sting" do
          let(:requirement_string) { "1.0.0-alpha" }
          it { is_expected.to eq(false) }
        end
      end

      context "for an out-of-range version" do
        let(:version_string) { "0.9.0" }
        it { is_expected.to eq(false) }
      end
    end
  end
end
