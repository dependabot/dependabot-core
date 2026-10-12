# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/blocked_version"

RSpec.describe Dependabot::Job::BlockedVersion do
  describe ".from_hash" do
    it "parses a blocked version" do
      blocked_version = described_class.from_hash(
        {
          "dependency-name" => "rails",
          "version-requirement" => "< 7",
          "reason" => "vulnerable"
        }
      )

      expect(blocked_version).to have_attributes(
        dependency_name: "rails",
        version_requirement: "< 7",
        reason: "vulnerable"
      )
    end

    it "drops malformed fields" do
      blocked_version = described_class.from_hash(
        {
          "dependency-name" => 1,
          "version-requirement" => [],
          "reason" => true
        }
      )

      expect(blocked_version).to have_attributes(
        dependency_name: nil,
        version_requirement: nil,
        reason: nil
      )
    end
  end
end
