# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/security_advisory_entry"

RSpec.describe Dependabot::Job::SecurityAdvisoryEntry do
  describe ".from_hash" do
    it "parses an advisory" do
      advisory = described_class.from_hash(
        {
          "dependency-name" => "rails",
          "affected-versions" => ["< 7.0.8"],
          "patched-versions" => [">= 7.0.8"],
          "unaffected-versions" => ["< 6"]
        }
      )

      expect(advisory).to have_attributes(
        dependency_name: "rails",
        affected_versions: ["< 7.0.8"],
        patched_versions: [">= 7.0.8"],
        unaffected_versions: ["< 6"]
      )
    end

    it "defaults nil arrays to empty" do
      advisory = described_class.from_hash(
        {
          "dependency-name" => "rails",
          "affected-versions" => nil
        }
      )

      expect(advisory).to have_attributes(
        affected_versions: [],
        patched_versions: [],
        unaffected_versions: []
      )
    end

    it "fails for a malformed array" do
      expect do
        described_class.from_hash(
          {
            "dependency-name" => "rails",
            "patched-versions" => ">= 7"
          }
        )
      end.to raise_error(TypeError, /patched-versions/)
    end
  end
end
