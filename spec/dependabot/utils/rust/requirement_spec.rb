# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/rust/requirement"

RSpec.describe Dependabot::Utils::Rust::Requirement do
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

    describe "wildcards" do
      context "with only a *" do
        let(:requirement_string) { "*" }
        it { is_expected.to eq(described_class.new(">= 0")) }
      end

      context "with a 1.*" do
        let(:requirement_string) { "1.*" }
        it { is_expected.to eq(described_class.new("~> 1.0")) }
      end

      context "with a 1.1.*" do
        let(:requirement_string) { "1.1.*" }
        it { is_expected.to eq(described_class.new("~> 1.1.0")) }

        context "prefixed with a caret" do
          let(:requirement_string) { "^1.1.*" }
          it { is_expected.to eq(described_class.new("~> 1.1.0")) }
        end
      end
    end

    context "with no specifier" do
      let(:requirement_string) { "1.1.0" }
      it { is_expected.to eq(described_class.new(">= 1.1.0", "< 2.0.0")) }
    end

    context "with a caret version" do
      context "specified to 3 dp" do
        let(:requirement_string) { "^1.2.3" }
        it { is_expected.to eq(described_class.new(">= 1.2.3", "< 2.0.0")) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2.3" }
          it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0")) }

          context "and a zero minor" do
            let(:requirement_string) { "^0.0.3" }
            it { is_expected.to eq(described_class.new(">= 0.0.3", "< 0.0.4")) }
          end
        end
      end

      context "specified to 2 dp" do
        let(:requirement_string) { "^1.2" }
        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0")) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2" }
          it { is_expected.to eq(described_class.new(">= 0.2", "< 0.3")) }

          context "and a zero minor" do
            let(:requirement_string) { "^0.0" }
            it { is_expected.to eq(described_class.new(">= 0.0", "< 0.1")) }
          end
        end
      end

      context "specified to 1 dp" do
        let(:requirement_string) { "^1" }
        it { is_expected.to eq(described_class.new(">= 1", "< 2")) }

        context "with a zero major" do
          let(:requirement_string) { "^0" }
          it { is_expected.to eq(described_class.new(">= 0", "< 1")) }
        end
      end
    end

    context "with a ~ version" do
      context "specified to 3 dp" do
        let(:requirement_string) { "~1.5.1" }
        it { is_expected.to eq(described_class.new("~> 1.5.1")) }
      end

      context "specified to 2 dp" do
        let(:requirement_string) { "~1.5" }
        it { is_expected.to eq(described_class.new("~> 1.5.0")) }
      end

      context "specified to 1 dp" do
        let(:requirement_string) { "~1" }
        it { is_expected.to eq(described_class.new("~> 1.0")) }
      end
    end

    context "with a > version specified" do
      let(:requirement_string) { ">1.5.1" }
      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end

    context "with an = version specified" do
      let(:requirement_string) { "=1.5" }
      it { is_expected.to eq(Gem::Requirement.new("1.5")) }
    end

    context "with an ~> version specified" do
      let(:requirement_string) { "~> 1.5.1" }
      it { is_expected.to eq(Gem::Requirement.new("~> 1.5.1")) }
    end

    context "with a comma separated list" do
      let(:requirement_string) { ">1.5.1, < 2.0.0" }
      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1", "< 2.0.0")) }
    end
  end
end
