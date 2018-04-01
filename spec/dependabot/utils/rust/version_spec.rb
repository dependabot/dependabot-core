# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/rust/version"

RSpec.describe Dependabot::Utils::Rust::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe "#to_s" do
    subject { version.to_s }

    context "with a non-prerelease" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq "1.0.0" }
    end

    context "with a normal prerelease" do
      let(:version_string) { "1.0.0.pre1" }
      it { is_expected.to eq "1.0.0.pre1" }
    end

    context "with a PHP-style prerelease" do
      let(:version_string) { "1.0.0-pre1" }
      it { is_expected.to eq "1.0.0-pre1" }
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

    context "with a valid prerelease version" do
      let(:version_string) { "1.1.0-pre" }
      it { is_expected.to eq(true) }
    end
  end
end
