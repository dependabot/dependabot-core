# frozen_string_literal: true

require "spec_helper"
require "dependabot/utils/java_script/requirement"
require "dependabot/utils/java_script/version"

RSpec.describe Dependabot::Utils::JavaScript::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }
  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with an exact version specified" do
      let(:requirement_string) { "1.0.0" }
      it { is_expected.to eq(described_class.new("1.0.0")) }
    end

    context "with a caret version specified" do
      let(:requirement_string) { "^1.0.0" }
      it { is_expected.to eq(described_class.new(">= 1.0.0", "< 2.0.0")) }
    end

    context "with a ~ version specified" do
      let(:requirement_string) { "~1.5.1" }
      it { is_expected.to eq(described_class.new("~> 1.5.1")) }
    end

    context "with a ~> version specified" do
      let(:requirement_string) { "~>1.5.1" }
      it { is_expected.to eq(described_class.new("~> 1.5.1")) }
    end

    context "with only a *" do
      let(:requirement_string) { "*" }
      it { is_expected.to eq(described_class.new("~> 0")) }
    end

    context "with a *" do
      let(:requirement_string) { "1.*" }
      it { is_expected.to eq(described_class.new("~> 1.0")) }
    end

    context "with an x" do
      let(:requirement_string) { "^1.1.x" }
      it { is_expected.to eq(described_class.new(">= 1.1", "< 2.0")) }
    end

    context "with a 'v' prefix" do
      let(:requirement_string) { ">=v1.0.0" }
      it { is_expected.to eq(described_class.new(">= v1.0.0")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a Gem::Version" do
      context "for the current version" do
        let(:version) { Gem::Version.new("1.0.0") }
        it { is_expected.to eq(true) }

        context "when the requirement includes a v prefix" do
          let(:requirement_string) { ">=v1.0.0" }
          it { is_expected.to eq(true) }
        end
      end

      context "for an out-of-range version" do
        let(:version) { Gem::Version.new("0.9.0") }
        it { is_expected.to eq(false) }
      end
    end

    context "with a Utils::JavaScript::Version" do
      let(:version) do
        Dependabot::Utils::JavaScript::Version.new(version_string)
      end

      context "for the current version" do
        let(:version_string) { "1.0.0" }
        it { is_expected.to eq(true) }

        context "that includes a 'v' prefix" do
          let(:version_string) { "v1.0.0" }
          it { is_expected.to eq(true) }
        end
      end
    end
  end
end
