# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/ignore_condition"

RSpec.describe Dependabot::Job::IgnoreCondition do
  describe ".from_hash" do
    it "parses an ignore condition" do
      condition = described_class.from_hash(
        {
          "dependency-name" => "rails",
          "version-requirement" => "< 7",
          "update-types" => ["version-update:semver-major"],
          "source" => "@dependabot ignore",
          "updated-at" => "2026-07-16T00:00:00Z"
        }
      )

      expect(condition).to have_attributes(
        dependency_name: "rails",
        version_requirement: "< 7",
        update_types: ["version-update:semver-major"],
        source: "@dependabot ignore",
        updated_at: "2026-07-16T00:00:00Z"
      )
    end

    it "fails when dependency-name is missing" do
      expect { described_class.from_hash({}) }.to raise_error(KeyError)
    end

    it "fails for malformed optional fields" do
      expect do
        described_class.from_hash(
          {
            "dependency-name" => "rails",
            "update-types" => "major"
          }
        )
      end.to raise_error(TypeError, /update-types/)
    end
  end
end
