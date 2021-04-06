# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/requirement"
require "dependabot/pub/version"

RSpec.describe Dependabot::Pub::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { "^1.0.0" }

  describe ".new" do
    subject { described_class.new(requirement_string) }

    context "with a specific version requirement" do
      let(:requirement_string) { "1.0.0" }
      it { is_expected.to be_satisfied_by(Dependabot::Pub::Version.new("1.0.0")) }
      it { is_expected.to_not be_satisfied_by(Dependabot::Pub::Version.new("1.0.1")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "for the current version" do
        let(:version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(true) }

        context "when the requirement includes a pre-release version" do
          let(:requirement_string) { ">=1.0.0-gc.1" }
          it { is_expected.to eq(true) }
        end
      end

      context "for an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(false) }
      end
    end

    context "with a Pub::Version" do
      let(:version) { Dependabot::Pub::Version.new(version_string) }

      context "for the current version" do
        let(:version_string) { "1.0.0" }
        it { is_expected.to eq(true) }

        context "when the requirement includes a pre-release version" do
          let(:requirement_string) { ">=1.0.0-rc.1" }
          it { is_expected.to eq(true) }

          context "that is satisfied by the version" do
            let(:version_string) { "1.0.0-rc.2" }
            it { is_expected.to eq(true) }
          end
        end
      end

      context "for an out-of-range version" do
        let(:version_string) { "0.9.0" }
        it { is_expected.to eq(false) }
      end

      context "for a pre-release version" do
        let(:version_string) { "1.0.0-rc.2" }
        it { is_expected.to eq(false) }
      end
    end
  end
end
