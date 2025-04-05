# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/version"

RSpec.describe Dependabot::Pub::Version do
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

    context "with a build version" do
      let(:version_string) { "1.0.0-pre1+something" }

      it { is_expected.to eq "1.0.0-pre1+something" }
    end

    context "with a blank version" do
      let(:version_string) { "" }

      it { is_expected.to eq "" }
    end

    context "with a version (not a version string)" do
      let(:version_string) { described_class.new("1.0.0") }

      it { is_expected.to eq "1.0.0" }
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }

      it { is_expected.to be(false) }
    end

    context "with a valid prerelease version" do
      let(:version_string) { "1.1.0-pre" }

      it { is_expected.to be(true) }
    end
  end

  describe "#correct?" do
    subject { described_class.correct?(version_string) }

    valid = %w(1.0.0 1.0.0.pre1 1.0.0-pre1 1.0.0-pre1+something)
    valid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(true) }
      end
    end

    invalid = %w(☃ questionmark?)
    invalid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(false) }
      end
    end
  end
end
