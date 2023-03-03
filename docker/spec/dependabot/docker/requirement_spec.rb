# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/requirement"
require "dependabot/docker/version"

RSpec.describe Dependabot::Docker::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq(Gem::Requirement.new("~> 4.2.5", ">= 4.2.5.1")) }
    end

    context "with a comma-separated string new" do
      let(:requirement_string) { "> 20.8.1.alpine3.18, < 20.9" }

      it { is_expected.to eq(Gem::Requirement.new("> 20.8.1.alpine3.18", "< 20.9")) }
    end

    context "with a collection of strings" do
      let(:requirement_string) { [">= 1.0.0", "< 2.0.0"] }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "< 2.0.0")) }
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement_string) { "> 20.8.1.alpine3.18, < 20.9" }

    context "with a Dependabot::Docker::Version" do
      context "when using the current version" do
        let(:version) { Dependabot::Docker::Version.new("20.9.0-alpine3.18") }

        it { is_expected.to be(false) }
      end
    end
  end
end
