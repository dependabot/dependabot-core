# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/allowed_update"

RSpec.describe Dependabot::Job::AllowedUpdate do
  describe ".from_hash" do
    it "parses an allowed update" do
      update = described_class.from_hash(
        {
          "dependency-name" => "rails",
          "dependency-type" => "direct",
          "update-type" => "security",
          "update-types" => ["version-update:semver-minor"]
        }
      )

      expect(update).to have_attributes(
        dependency_name: "rails",
        dependency_type: "direct",
        update_type: "security",
        update_types: ["version-update:semver-minor"]
      )
    end

    it "uses defaults for absent or nil values" do
      update = described_class.from_hash(
        {
          "dependency-type" => nil,
          "update-type" => nil,
          "update-types" => nil
        }
      )

      expect(update).to have_attributes(
        dependency_name: nil,
        dependency_type: "all",
        update_type: "all",
        update_types: []
      )
    end

    it "fails for a malformed dependency name" do
      expect do
        described_class.from_hash("dependency-name" => 1)
      end.to raise_error(TypeError, /dependency-name/)
    end
  end
end
