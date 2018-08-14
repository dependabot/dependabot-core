# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/python/requirement"
require "dependabot/utils/python/version"

RSpec.describe Dependabot::Utils::Python::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with nil" do
      let(:requirement_string) { nil }
      it { is_expected.to eq(described_class.new(">= 0")) }
      it { is_expected.to be_a(described_class) }
    end

    context "with only an *" do
      let(:requirement_string) { "*" }
      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a ~=" do
      let(:requirement_string) { "~= 1.3.0" }
      it { is_expected.to eq(Gem::Requirement.new("~> 1.3.0")) }
    end

    context "with a ==" do
      let(:requirement_string) { "== 1.3.0" }
      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.0")) }
      it { is_expected.to_not be_satisfied_by(Gem::Version.new("1.3.1")) }
    end

    context "with a ===" do
      let(:requirement_string) { "=== 1.3.0" }

      it "implements arbitrary equality" do
        expect(requirement).
          to be_satisfied_by(Dependabot::Utils::Python::Version.new("1.3.0"))
        expect(requirement).
          to_not be_satisfied_by(Dependabot::Utils::Python::Version.new("1.3"))
      end
    end

    context "with a ~" do
      let(:requirement_string) { "~1.2.3" }
      it { is_expected.to eq(Gem::Requirement.new("~> 1.2.3")) }

      context "for two digits" do
        let(:requirement_string) { "~1.2" }
        it { is_expected.to eq(Gem::Requirement.new("~> 1.2.0")) }
      end

      context "for one digits" do
        let(:requirement_string) { "~1" }
        it { is_expected.to eq(Gem::Requirement.new("~> 1.0")) }
      end
    end

    context "with a ^" do
      let(:requirement_string) { "^1.2.3" }
      it { is_expected.to eq(described_class.new(">= 1.2.3", "< 2.0.0.a")) }

      context "for two digits" do
        let(:requirement_string) { "^1.2" }
        it { is_expected.to eq(described_class.new(">= 1.2", "< 2.0.0.a")) }
      end

      context "with a pre-1.0.0 dependency" do
        let(:requirement_string) { "^0.2.3" }
        it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0.a")) }
      end
    end

    context "with an *" do
      let(:requirement_string) { "== 1.3.*" }
      it { is_expected.to eq(Gem::Requirement.new("~> 1.3.0")) }
    end

    context "with another operator after the first" do
      let(:requirement_string) { ">=2.0<2.1" }
      # Python ignores that second operator!
      it { is_expected.to eq(Gem::Requirement.new(">=2.0")) }

      context "separated with a comma" do
        let(:requirement_string) { ">=2.0,<2.1" }
        it { is_expected.to eq(Gem::Requirement.new(">=2.0", "<2.1")) }
      end
    end

    context "with an array" do
      let(:requirement_string) { ["== 1.3.*", ">= 1.3.1"] }
      it { is_expected.to eq(Gem::Requirement.new([">= 1.3.1", "~> 1.3.0"])) }
    end

    context "with a pre-release version" do
      let(:requirement_string) { "== 1.3.alpha" }
      it { is_expected.to be_satisfied_by(Gem::Version.new("1.3.a")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "for the current version" do
        let(:version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(true) }

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }
          it { is_expected.to eq(false) }
        end
      end

      context "for an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(false) }
      end
    end

    context "with a Utils::Python::Version" do
      let(:version) do
        Dependabot::Utils::Python::Version.new(version_string)
      end

      context "for the current version" do
        let(:version_string) { "1.0.0" }
        it { is_expected.to eq(true) }

        context "that includes a local version" do
          let(:version_string) { "1.0.0+gc.1" }
          it { is_expected.to eq(true) }
        end

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }
          it { is_expected.to eq(false) }

          context "that is satisfied by the version" do
            let(:version_string) { "1.0.0+gc.2" }
            it { is_expected.to eq(true) }
          end
        end
      end

      context "for an out-of-range version" do
        let(:version_string) { "0.9.0" }
        it { is_expected.to eq(false) }
      end
    end
  end
end
