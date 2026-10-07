# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/cooldown_definition"

RSpec.describe Dependabot::Job::CooldownDefinition do
  describe ".from_hash" do
    subject(:definition) { described_class.from_hash(cooldown_hash) }

    let(:cooldown_hash) do
      {
        "default-days" => 7,
        "semver-major-days" => 14,
        "semver-minor-days" => 5,
        "semver-patch-days" => 2,
        "include" => ["rails"],
        "exclude" => ["rack"]
      }
    end

    it "parses cooldown fields" do
      expect(definition).to have_attributes(
        default_days: 7,
        semver_major_days: 14,
        semver_minor_days: 5,
        semver_patch_days: 2,
        include: ["rails"],
        exclude: ["rack"]
      )
    end

    context "with malformed fields" do
      let(:cooldown_hash) { super().merge("default-days" => "7") }

      it "fails fast" do
        expect { definition }.to raise_error(TypeError, /default-days/)
      end
    end
  end

  describe "#to_options" do
    it "uses the supplied fallback when default-days is absent" do
      definition = described_class.from_hash(
        {
          "include" => ["rails"],
          "exclude" => []
        }
      )

      expect(definition.to_options(default_days: 3)).to have_attributes(
        default_days: 3,
        semver_major_days: 3,
        semver_minor_days: 3,
        semver_patch_days: 3
      )
    end

    it "preserves an explicit zero default" do
      definition = described_class.from_hash("default-days" => 0)

      expect(definition.to_options(default_days: 3).default_days).to eq(0)
    end
  end
end
