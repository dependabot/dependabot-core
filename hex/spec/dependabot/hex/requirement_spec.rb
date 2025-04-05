# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/requirement"
require "dependabot/hex/version"

RSpec.describe Dependabot::Hex::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with a comma-separated string" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq(described_class.new("~> 4.2.5", ">= 4.2.5.1")) }
    end

    context "with an == specifier" do
      let(:requirement_string) { "== 1.0.0" }

      it { is_expected.to be_satisfied_by(Gem::Version.new("1.0.0")) }
      it { is_expected.not_to be_satisfied_by(Gem::Version.new("1.0.1")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "when using the current version" do
        let(:version) { Gem::Version.new("1.0.0") }

        it { is_expected.to be(true) }

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }

          it { is_expected.to be(false) }
        end
      end

      context "when using an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }

        it { is_expected.to be(false) }
      end
    end

    context "with a Hex::Version" do
      let(:version) { Dependabot::Hex::Version.new(version_string) }

      context "when using the current version" do
        let(:version_string) { "1.0.0" }

        it { is_expected.to be(true) }

        context "when the specification includes a local version" do
          let(:version_string) { "1.0.0+gc.1" }

          it { is_expected.to be(true) }
        end

        context "when the requirement includes a local version" do
          let(:requirement_string) { ">=1.0.0+gc.1" }

          it { is_expected.to be(false) }

          context "when the specification is satisfied by the version" do
            let(:version_string) { "1.0.0+gc.2" }

            it { is_expected.to be(true) }
          end
        end
      end

      context "when using an out-of-range version" do
        let(:version_string) { "0.9.0" }

        it { is_expected.to be(false) }
      end
    end
  end
end
