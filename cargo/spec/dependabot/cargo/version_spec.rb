# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/version"

RSpec.describe Dependabot::Cargo::Version do
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

    context "with a build version with hypens" do
      let(:version_string) { "0.9.0+wasi-snapshot-preview1" }
      it { is_expected.to eq "0.9.0+wasi-snapshot-preview1" }
    end

    context "with a build version with hypens in multiple identifiers" do
      let(:version_string) { "0.9.0+wasi-snapshot1.alpha-preview" }
      it { is_expected.to eq "0.9.0+wasi-snapshot1.alpha-preview" }
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

  describe "#correct?" do
    subject { described_class.correct?(version_string) }

    valid = %w(1.0.0 1.0.0.pre1 1.0.0-pre1 1.0.0-pre1+something 0.9.0+wasi-snapshot-preview1
               0.9.0+wasi-snapshot1.alpha-preview)
    valid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }
        it { is_expected.to eq(true) }
      end
    end

    invalid = %w(☃ questionmark?)
    invalid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }
        it { is_expected.to eq(false) }
      end
    end
  end
end
