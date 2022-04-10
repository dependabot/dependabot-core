# frozen_string_literal: true

require "spec_helper"
require "dependabot/cocoapods/version"

RSpec.describe Dependabot::CocoaPods::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe "#to_s" do
    subject { version.to_s }

    context "with a valid string" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
    end
  end

  describe "#<=>" do
    subject { version <=> other_version }

    context "compared to a Gem::Version" do
      context "that is lower" do
        let(:other_version) { Pod::Version.new("0.9.0") }
        it { is_expected.to eq(1) }
      end

      context "that is equal" do
        let(:other_version) { Pod::Version.new("1.0.0") }
        it { is_expected.to eq(0) }
      end

      context "that is greater" do
        let(:other_version) { Pod::Version.new("1.1.0") }
        it { is_expected.to eq(-1) }
      end
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }
    let(:requirement) { Pod::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }
      it { is_expected.to eq(false) }
    end
  end
end
