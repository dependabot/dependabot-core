# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/constraint_helper"
require "dependabot/bun/version"

RSpec.describe Dependabot::Bun::ConstraintHelper do
  describe ".find_highest_version_from_constraint_expression" do
    it "honors every constraint in an AND group" do
      supported_versions = [Dependabot::Bun::Version.new("1.1.39")]

      result = described_class.find_highest_version_from_constraint_expression(">=2 <3", supported_versions)

      expect(result).to be_nil
    end

    it "handles constraints separated by a whitespace-padded comma" do
      supported_versions = %w(1.1.39 2.0.0).map { |version| Dependabot::Bun::Version.new(version) }

      result = described_class.find_highest_version_from_constraint_expression(">= 1.0.0 , < 2.0.0", supported_versions)

      expect(result).to eq("1.1.39")
    end

    it "returns nil for empty constraints" do
      supported_versions = [Dependabot::Bun::Version.new("1.1.39")]

      [nil, "", "   "].each do |constraint|
        expect(described_class.find_highest_version_from_constraint_expression(constraint, supported_versions))
          .to be_nil
      end
    end
  end
end
