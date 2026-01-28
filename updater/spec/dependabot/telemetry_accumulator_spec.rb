# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/telemetry_accumulator"

RSpec.describe Dependabot::TelemetryAccumulator do
  describe "#add_ecosystem_versions" do
    it "accumulates ecosystem versions" do
      accumulator = described_class.new
      versions1 = { ruby: { min: "3.0", max: "3.2" } }
      versions2 = { node: { min: "18", max: "20" } }

      accumulator.add_ecosystem_versions(versions1)
      accumulator.add_ecosystem_versions(versions2)

      expect(accumulator.ecosystem_versions).to eq([versions1, versions2])
    end
  end

  describe "#add_ecosystem_meta" do
    it "accumulates ecosystem metadata" do
      accumulator = described_class.new
      meta1 = { ecosystem: { name: "bundler" } }
      meta2 = { ecosystem: { name: "npm_and_yarn" } }

      accumulator.add_ecosystem_meta(meta1)
      accumulator.add_ecosystem_meta(meta2)

      expect(accumulator.ecosystem_meta).to eq([meta1, meta2])
    end

    it "ignores nil metadata" do
      accumulator = described_class.new
      accumulator.add_ecosystem_meta(nil)

      expect(accumulator.ecosystem_meta).to be_empty
    end
  end

  describe "#add_cooldown_meta" do
    it "accumulates cooldown metadata" do
      accumulator = described_class.new
      cooldown1 = { cooldown: { ecosystem_name: "bundler" } }
      cooldown2 = { cooldown: { ecosystem_name: "npm_and_yarn" } }

      accumulator.add_cooldown_meta(cooldown1)
      accumulator.add_cooldown_meta(cooldown2)

      expect(accumulator.cooldown_meta).to eq([cooldown1, cooldown2])
    end

    it "ignores nil metadata" do
      accumulator = described_class.new
      accumulator.add_cooldown_meta(nil)

      expect(accumulator.cooldown_meta).to be_empty
    end
  end

  describe "#empty?" do
    it "returns true when no data accumulated" do
      accumulator = described_class.new
      expect(accumulator).to be_empty
    end

    it "returns false when ecosystem versions added" do
      accumulator = described_class.new
      accumulator.add_ecosystem_versions({ ruby: { min: "3.0" } })
      expect(accumulator).not_to be_empty
    end

    it "returns false when ecosystem meta added" do
      accumulator = described_class.new
      accumulator.add_ecosystem_meta({ ecosystem: { name: "bundler" } })
      expect(accumulator).not_to be_empty
    end

    it "returns false when cooldown meta added" do
      accumulator = described_class.new
      accumulator.add_cooldown_meta({ cooldown: { ecosystem_name: "bundler" } })
      expect(accumulator).not_to be_empty
    end
  end

  describe "#to_h" do
    it "returns all accumulated data as hash" do
      accumulator = described_class.new
      versions = { ruby: { min: "3.0" } }
      meta = { ecosystem: { name: "bundler" } }
      cooldown = { cooldown: { ecosystem_name: "bundler" } }

      accumulator.add_ecosystem_versions(versions)
      accumulator.add_ecosystem_meta(meta)
      accumulator.add_cooldown_meta(cooldown)

      expect(accumulator.to_h).to eq(
        {
          ecosystem_versions: [versions],
          ecosystem_meta: [meta],
          cooldown_meta: [cooldown]
        }
      )
    end
  end

  describe "thread safety" do
    it "safely accumulates from multiple threads" do
      accumulator = described_class.new
      threads = []

      10.times do |i|
        threads << Thread.new do
          accumulator.add_ecosystem_versions({ index: i })
        end
      end

      threads.each(&:join)

      expect(accumulator.ecosystem_versions.length).to eq(10)
    end
  end
end
