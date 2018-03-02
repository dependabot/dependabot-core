# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/python/pip/requirement"
require "dependabot/update_checkers/python/pip/version"

RSpec.describe Dependabot::UpdateCheckers::Python::Pip::Requirement do
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
      it { is_expected.to eq(Gem::Requirement.new("= 1.3.0")) }
    end

    context "with an *" do
      let(:requirement_string) { "== 1.3.*" }
      it { is_expected.to eq(Gem::Requirement.new("~> 1.3.0")) }
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

    context "with a Pip::Version" do
      let(:version) do
        Dependabot::UpdateCheckers::Python::Pip::Version.new(version_string)
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
