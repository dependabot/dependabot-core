# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/dependency_group_definition"

RSpec.describe Dependabot::Job::DependencyGroupDefinition do
  describe ".from_hash" do
    it "parses a dependency group" do
      definition = described_class.from_hash(
        {
          "name" => "production",
          "applies-to" => "version-updates",
          "rules" => {
            "patterns" => ["*"],
            "exclude-patterns" => ["rubocop"],
            "dependency-type" => "production"
          }
        }
      )

      expect(definition).to have_attributes(
        name: "production",
        applies_to: "version-updates",
        rules: {
          "patterns" => ["*"],
          "exclude-patterns" => ["rubocop"],
          "dependency-type" => "production"
        }
      )
    end

    it "drops malformed fields" do
      definition = described_class.from_hash(
        {
          "name" => 1,
          "applies-to" => [],
          "rules" => "all"
        }
      )

      expect(definition).to have_attributes(name: nil, applies_to: nil, rules: nil)
    end
  end

  describe "#to_h" do
    it "preserves open-ended rule values" do
      definition = described_class.from_hash(
        {
          "name" => "production",
          "rules" => { "patterns" => ["*"], "dependency-type" => "production" }
        }
      )

      expect(definition.to_h).to eq(
        "name" => "production",
        "rules" => { "patterns" => ["*"], "dependency-type" => "production" }
      )
    end
  end
end
