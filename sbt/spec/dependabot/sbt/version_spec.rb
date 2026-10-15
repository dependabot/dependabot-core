# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/version"

RSpec.describe Dependabot::Sbt::Version do
  extend T::Sig

  sig { returns(Dependabot::Version) }
  subject(:version) { described_class.new(version_string) }

  sig { returns(T.nilable(String)) }
  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    sig { returns(T::Boolean) }
    subject { described_class.correct?(version_string) }

    context "with a normal version" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with a named version" do
      sig { override.returns(String) }
      let(:version_string) { "Finchley" }

      it { is_expected.to be(true) }
    end

    context "with a dynamic version" do
      sig { override.returns(String) }
      let(:version_string) { "1.+" }

      it { is_expected.to be(true) }
    end

    context "with a nil version" do
      sig { override.returns(NilClass) }
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with an empty version" do
      sig { override.returns(String) }
      let(:version_string) { "" }

      it { is_expected.to be(false) }
    end
  end

  describe "#to_s" do
    sig { returns(String) }
    subject { version.to_s }

    context "with no dashes" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq("1.0.0") }
    end

    context "with a dash-specified prerelease" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0-rc1" }

      it { is_expected.to eq("1.0.0-rc1") }
    end

    context "with underscores" do
      sig { override.returns(String) }
      let(:version_string) { "1.0_2" }

      it { is_expected.to eq("1.0_2") }
    end
  end

  describe "#prerelease?" do
    sig { returns(T::Boolean) }
    subject { version.prerelease? }

    context "with an alpha version" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0-alpha" }

      it { is_expected.to be(true) }
    end

    context "with an RC version" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0-rc1" }

      it { is_expected.to be(true) }
    end

    context "with a SNAPSHOT version" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0-SNAPSHOT" }

      it { is_expected.to be(true) }
    end

    context "with a stable version" do
      sig { override.returns(String) }
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(false) }
    end
  end

  describe "comparison" do
    context "when comparing to another version" do
      it "orders correctly" do
        expect(described_class.new("1.0.0")).to be < described_class.new("1.0.1")
        expect(described_class.new("1.0.0")).to be < described_class.new("2.0.0")
        expect(described_class.new("1.0.0-alpha")).to be < described_class.new("1.0.0")
        expect(described_class.new("1.0.0-SNAPSHOT")).to be < described_class.new("1.0.0")
      end
    end
  end
end
