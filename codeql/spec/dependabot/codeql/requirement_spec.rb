# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/codeql/requirement"
require "dependabot/codeql/version"

RSpec.describe Dependabot::Codeql::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  describe "#satisfied_by?" do
    context "with a caret range on a 0.minor version" do
      let(:requirement_string) { "^0.9.1" }

      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.1")) }
      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.9")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("0.10.0")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.0")) }
    end

    context "with a caret range on a major version" do
      let(:requirement_string) { "^1.2.3" }

      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("1.9.9")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("2.0.0")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("1.2.2")) }
    end

    context "with a wildcard" do
      let(:requirement_string) { "*" }

      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("0.0.1")) }
      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("99.0.0")) }
    end

    context "with a plain version" do
      let(:requirement_string) { "0.9.1" }

      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.1")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.2")) }
    end

    context "with a standard comparison operator" do
      let(:requirement_string) { ">= 0.9.0" }

      it { is_expected.to be_satisfied_by(Dependabot::Codeql::Version.new("1.0.0")) }
      it { is_expected.not_to be_satisfied_by(Dependabot::Codeql::Version.new("0.8.9")) }
    end
  end

  describe ".requirements_array" do
    it "wraps a single requirement string" do
      array = described_class.requirements_array("^0.9.1")
      expect(array.size).to eq(1)
      expect(array.first).to be_satisfied_by(Dependabot::Codeql::Version.new("0.9.5"))
    end
  end
end
