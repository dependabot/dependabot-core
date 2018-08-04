# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/elm/requirement"
require "dependabot/utils/elm/version"

RSpec.describe Dependabot::Utils::Elm::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { "1.0.0 <= v < 2.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with nil" do
      let(:requirement_string) { nil }
      it "raises a helpful error" do
        expect { subject }.to raise_error(Gem::Requirement::BadRequirementError)
      end
    end

    context "with range requirement" do
      let(:requirement_string) { "1.0.0 <= v < 2.0.0" }
      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "< 2.0.0")) }

      context "which uses a <= operator" do
        let(:requirement_string) { "1.0.0 <= v <= 2.0.0" }
        it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 2.0.0")) }
      end
    end

    context "with exact requirement" do
      let(:requirement_string) { "1.0.0 <= v <= 1.0.0" }
      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
      it { is_expected.to be_satisfied_by(Gem::Version.new("1.0.0")) }
      it { is_expected.to_not be_satisfied_by(Gem::Version.new("1.0.1")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "for the current version" do
        let(:version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(true) }
      end

      context "for an out-of-range version" do
        let(:version) { Gem::Version.new("2.0.1") }
        it { is_expected.to eq(false) }
      end
    end

    context "with a Utils::Elm::Version" do
      let(:version) do
        Dependabot::Utils::Elm::Version.new(version_string)
      end

      context "for the current version" do
        let(:version_string) { "1.0.0" }
        it { is_expected.to eq(true) }
      end

      context "for an out-of-range version" do
        let(:version_string) { "2.0.1" }
        it { is_expected.to eq(false) }
      end
    end
  end
end
