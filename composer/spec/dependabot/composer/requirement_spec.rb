# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/requirement"

RSpec.describe Dependabot::Composer::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { ">= 1.0.0, < 1.2.1" }
      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "< 1.2.1")) }
    end

    context "with a stability constraint" do
      let(:requirement_string) { ">=1.0.0@dev" }
      it { is_expected.to eq(described_class.new(">=1.0.0")) }
    end

    context "with just a stability constraint" do
      let(:requirement_string) { "@dev" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with an alias" do
      let(:requirement_string) { ">=whatever as 1.0.0" }
      it { is_expected.to eq(described_class.new(">=1.0.0")) }
    end

    context "with a v-prefixed version" do
      let(:requirement_string) { ">= v1.0.0" }
      it { is_expected.to eq(described_class.new(">= 1.0.0")) }
    end

    context "with a caret version specified" do
      let(:requirement_string) { "^1.0.0" }
      it { is_expected.to eq(described_class.new(">= 1.0.0", "< 2.0.0")) }
    end

    context "with a caret version and dev postfix" do
      let(:requirement_string) { "^7.x-dev" }
      it { is_expected.to eq(described_class.new(">= 7.0", "< 8.0")) }
    end

    context "with a ~ version specified" do
      let(:requirement_string) { "~1.5.1" }
      it { is_expected.to eq(described_class.new("~> 1.5.1")) }
    end

    context "with a ~> version specified" do
      let(:requirement_string) { "~>1.5.1" }
      it { is_expected.to eq(described_class.new("~> 1.5.1")) }
    end

    context "with only a *" do
      let(:requirement_string) { "*" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with only a x" do
      let(:requirement_string) { "x" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a *" do
      let(:requirement_string) { "1.*" }
      it { is_expected.to eq(described_class.new("~> 1.0")) }

      context "in a range" do
        let(:requirement_string) { ">= 1.x" }

        it "raises a Gem::Requirement::BadRequirementError error" do
          expect { requirement }.
            to raise_error(Gem::Requirement::BadRequirementError) do |error|
              expect(error.message).to eq("Illformed requirement [\">= 1.x\"]")
            end
        end
      end
    end

    context "with a x" do
      let(:requirement_string) { "1.x" }
      it { is_expected.to eq(described_class.new("~> 1.0")) }

      context "in a range" do
        let(:requirement_string) { ">= 1.x" }

        it "raises a Gem::Requirement::BadRequirementError error" do
          expect { requirement }.
            to raise_error(Gem::Requirement::BadRequirementError) do |error|
              expect(error.message).to eq("Illformed requirement [\">= 1.x\"]")
            end
        end
      end
    end

    context "with a trailing ." do
      let(:requirement_string) { "1." }
      it { is_expected.to eq(described_class.new("1")) }
    end
  end
end
