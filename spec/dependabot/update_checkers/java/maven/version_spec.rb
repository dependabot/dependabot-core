# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java/maven/version"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe "#to_s" do
    subject { version.to_s }

    context "with no dashes" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
    end

    context "with a dot-specified prerelease" do
      let(:version_string) { "1.0.0.pre1" }
      it { is_expected.to eq "1.0.0.pre1" }
    end

    context "with a dash-specified prerelease" do
      let(:version_string) { "1.0.0-pre1" }
      it { is_expected.to eq "1.0.0-pre1" }
    end

    context "with an underscore-specified prerelease" do
      let(:version_string) { "1.0.0_pre1" }
      it { is_expected.to eq "1.0.0_pre1" }
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }
    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }
      it { is_expected.to eq(false) }
    end

    context "with a valid dash-separated version" do
      let(:version_string) { "1.1.0-pre" }
      it { is_expected.to eq(true) }
    end
  end
end
