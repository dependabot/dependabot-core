# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/requirement"
require "dependabot/nuget/version"

RSpec.describe Dependabot::Nuget::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with only a *" do
      let(:requirement_string) { "*" }

      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a *" do
      let(:requirement_string) { "1.*" }

      it { is_expected.to eq(described_class.new("~> 1.0")) }

      context "when specifying pre-release versions" do
        let(:requirement_string) { "1.1-*" }

        it { is_expected.to eq(described_class.new("~> 1.1-a")) }
      end

      context "when specifying highest version and pre-release versions" do
        let(:requirement_string) { "*-*" }

        it { is_expected.to eq(described_class.new(">= 0-a")) }
      end
    end

    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0")) }

      context "when a > operator is needed" do
        let(:requirement_string) { "(1.0.0,)" }

        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0")) }
      end

      context "when a > and a < operator is needed" do
        let(:requirement_string) { "(1.0.0, 2.0.0)" }

        it { is_expected.to eq(Gem::Requirement.new("> 1.0.0", "< 2.0.0")) }
      end

      context "when a >= and a <= operator is needed" do
        let(:requirement_string) { "[ 1.0.0,2.0.0 ]" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 2.0.0")) }
      end

      context "when specified in Ruby format" do
        let(:requirement_string) { ">= 1.0.0, < 2.0.0" }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "< 2.0.0")) }
      end

      context "when an empty string follows a comma" do
        let(:requirement_string) { ">= 1.40.0, " }

        it { is_expected.to eq(Gem::Requirement.new(">= 1.40.0")) }
      end

      context "when including a * in the lower bound" do
        let(:requirement_string) { "[2.1.*,3.0.0)" }

        it { is_expected.to eq(Gem::Requirement.new(">= 2.1.0", "< 3.0.0")) }
      end

      context "when including a * in the upper bound" do
        let(:requirement_string) { "[2.1,3.0.*)" }

        it { is_expected.to eq(Gem::Requirement.new(">= 2.1", "< 3.0.0")) }
      end
    end
  end
end
