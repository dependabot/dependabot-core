# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven_osv/requirement"
require "dependabot/maven_osv/version"

RSpec.describe Dependabot::MavenOSV::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject(:requirement) { described_class.new(requirement_string) }

    context "with a pre-release version" do
      let(:requirement_string) { "1.3.alpha" }

      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.alpha")) }
    end

    context "with a version that wouldn't be a valid Gem::Version" do
      let(:requirement_string) { ">= Finchley.SR3" }

      it "creates a requirement object" do
        expect(requirement).to be_satisfied_by(
          Dependabot::MavenOSV::Version.new("Finchley.SR4")
        )
      end
    end

    context "with a requirement ending with build metadata" do
      let(:requirement_string) { "1.0.0+92" }

      it "creates a requirement object" do
        expect(requirement).to be_satisfied_by(
          Dependabot::MavenOSV::Version.new("1.0.0+92")
        )
      end
    end

    context "with a version that has underscores" do
      let(:requirement_string) { "[2.2.1_CODICE_1]" }

      it "creates a requirement object" do
        expect(requirement).to be_satisfied_by(
          Dependabot::MavenOSV::Version.new("2.2.1_CODICE_1")
        )
      end
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

      context "when specifying a minimum" do
        let(:requirement_string) { "1.5+" }

        its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.5").to_s) }
      end

      context "when the requirement version is +" do
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
        expect(array).to contain_exactly(described_class.new("> 1.0.0"), described_class.new("< 1.0.0"))
      end
    end

    context "with a comma-separated ruby style version requirement" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq([described_class.new("~> 4.2.5", ">= 4.2.5.1")]) }
    end

    context "with a comma-separated ruby style requirement with maven versions" do
      let(:requirement_string) { ">= Finchley.a, < Finchley.999999" }

      it { is_expected.to eq([described_class.new(">= Finchley.a", "< Finchley.999999")]) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "when dealing with the current version" do
        let(:version) { Gem::Version.new("1.0.0") }

        it { is_expected.to be(true) }

        context "when the requirement includes a post-release" do
          let(:requirement_string) { ">=1.0.0u2" }

          it { is_expected.to be(false) }
        end
      end

      context "when dealing with an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }

        it { is_expected.to be(false) }
      end
    end

    context "with a MavenOSV::Version" do
      let(:version) do
        Dependabot::MavenOSV::Version.new(version_string)
      end

      context "when dealing with the current version" do
        let(:version_string) { "1.0.0" }

        it { is_expected.to be(true) }

        context "when dealing with a post-release version" do
          let(:version_string) { "1.0.0u2" }

          it { is_expected.to be(true) }
        end

        context "when dealing with a pre-release string" do
          let(:requirement_string) { "1.0.0-alpha" }

          it { is_expected.to be(false) }
        end
      end

      context "when dealing with an out-of-range version" do
        let(:version_string) { "0.9.0" }

        it { is_expected.to be(false) }
      end
    end
  end
end
