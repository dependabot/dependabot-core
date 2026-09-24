# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/apm/requirement"

RSpec.describe Dependabot::Apm::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">= 1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a comma-separated string" do
      let(:requirement_string) { "~> 1.2.0, >= 1.2.3" }

      it "splits the requirement on the comma" do
        expect(requirement).to eq(described_class.new("~> 1.2.0", ">= 1.2.3"))
      end
    end
  end

  describe ".requirements_array" do
    subject { described_class.requirements_array(requirement_string) }

    let(:requirement_string) { ">= 1.0.0" }

    it "returns a single-element array" do
      expect(described_class.requirements_array(requirement_string))
        .to eq([described_class.new(">= 1.0.0")])
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement_string) { ">= 1.0.0" }

    context "when the version satisfies the requirement" do
      let(:version) { Dependabot::Apm::Version.new("1.2.0") }

      it { is_expected.to be(true) }
    end

    context "when the version does not satisfy the requirement" do
      let(:version) { Dependabot::Apm::Version.new("0.9.0") }

      it { is_expected.to be(false) }
    end
  end
end
