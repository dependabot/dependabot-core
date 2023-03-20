# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/requirement"

RSpec.describe Dependabot::Pub::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a blank string" do
      let(:requirement_string) { "" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a pre-release" do
      let(:requirement_string) { "4.0.0-beta3" }
      it "preserves the pre-release formatting" do
        expect(requirement.requirements.first.last.to_s).to eq("4.0.0-beta3")
      end
    end

    context "with a build-version" do
      let(:requirement_string) { "4.0.0+something" }
      it "preserves the build version" do
        expect(requirement.requirements.first.last.to_s).
          to eq("4.0.0+something")
      end
    end

    context "with no specifier" do
      let(:requirement_string) { "1.1.0" }
      it { is_expected.to eq(described_class.new("= 1.1.0")) }
    end

    context "with a caret version" do
      context "specified to version" do
        let(:requirement_string) { "^1.2.3" }
        d = described_class.new(">=1.2.3", "<2.0.0")
        it { is_expected.to eq(d) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2.3" }
          it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0")) }

          context "and a zero minor" do
            let(:requirement_string) { "^0.0.3" }
            it { is_expected.to eq(described_class.new(">= 0.0.3", "< 0.0.4")) }
          end
        end
      end
    end

    context "with a > version specified" do
      let(:requirement_string) { ">1.5.1" }
      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end
    context "with lower bound" do
      let(:requirement_string) { ">1.5.1" }
      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end

    context "with upper bound" do
      let(:requirement_string) { "<2.0.0" }
      it { is_expected.to eq(Gem::Requirement.new("< 2.0.0")) }
    end

    context "with lower and upper bound" do
      let(:requirement_string) { ">1.2.3 <2.0.0" }
      it { is_expected.to eq(Gem::Requirement.new("> 1.2.3", "< 2.0.0")) }
    end
  end
end
