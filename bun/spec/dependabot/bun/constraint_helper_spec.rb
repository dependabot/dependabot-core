# typed: strict
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
  end
end
