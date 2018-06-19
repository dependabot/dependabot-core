# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/java/requirement"
require "dependabot/utils/java/version"

RSpec.describe Dependabot::Utils::Java::Requirement do
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
          Dependabot::Utils::Java::Version.new("Finchley.SR4")
        )
      end
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

    context "with a Utils::Java::Version" do
      let(:version) do
        Dependabot::Utils::Java::Version.new(version_string)
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
