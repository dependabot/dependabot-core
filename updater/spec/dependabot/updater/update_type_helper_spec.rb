# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/update_type_helper"

RSpec.describe Dependabot::Updater::UpdateTypeHelper do
  # Create a test class that includes the module
  let(:helper_class) do
    Class.new do
      include Dependabot::Updater::UpdateTypeHelper
    end
  end

  let(:helper) { helper_class.new }

  describe "#semver_parts" do
    context "when version responds to semver_parts" do
      it "returns SemverParts from the version's semver_parts method" do
        version = instance_double("Version", semver_parts: [1, 2, 3])

        result = helper.semver_parts(version)

        expect(result).to be_a(Dependabot::Updater::UpdateTypeHelper::SemverParts)
        expect(result.major).to eq(1)
        expect(result.minor).to eq(2)
        expect(result.patch).to eq(3)
      end

      it "returns nil when semver_parts returns nil" do
        version = instance_double("Version", semver_parts: nil)
        allow(version).to receive(:respond_to?).with(:semver_parts).and_return(true)
        allow(version).to receive(:respond_to?).with(:segments).and_return(false)

        result = helper.semver_parts(version)

        expect(result).to be_nil
      end
    end

    context "when version responds to segments" do
      context "with integer segments" do
        it "returns SemverParts for [1, 2, 3]" do
          version = instance_double("Version", segments: [1, 2, 3])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(3)
        end

        it "returns SemverParts with zero defaults for partial versions" do
          version = instance_double("Version", segments: [1])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end
      end

      context "with string numeric segments" do
        it "converts string segments to integers" do
          version = instance_double("Version", segments: ["1", "2", "3"])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(3)
        end
      end

      context "with 'v' prefix in segments" do
        it "strips 'v' prefix and extracts numeric parts for ['v', 1, 0, 0]" do
          version = instance_double("Version", segments: ["v", 1, 0, 0])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end

        it "strips 'v' prefix and extracts numeric parts for ['v', '1', '1', '1']" do
          version = instance_double("Version", segments: ["v", "1", "1", "1"])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(1)
          expect(result.patch).to eq(1)
        end

        it "handles v2.3.4 correctly" do
          version = instance_double("Version", segments: ["v", 2, 3, 4])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result.major).to eq(2)
          expect(result.minor).to eq(3)
          expect(result.patch).to eq(4)
        end
      end

      context "with non-numeric segments" do
        it "returns nil when all segments are non-numeric" do
          version = instance_double("Version", segments: ["alpha", "beta", "gamma"])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end

      context "with empty segments" do
        it "returns nil for empty array" do
          version = instance_double("Version", segments: [])
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
          allow(version).to receive(:respond_to?).with(:segments).and_return(true)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end
    end

    context "when version does not respond to segments" do
      it "returns nil" do
        version = instance_double("Version")
        allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)
        allow(version).to receive(:respond_to?).with(:segments).and_return(false)

        result = helper.semver_parts(version)

        expect(result).to be_nil
      end
    end
  end

  describe "#numeric_segment?" do
    it "returns true for integers" do
      expect(helper.numeric_segment?(1)).to be true
      expect(helper.numeric_segment?(0)).to be true
      expect(helper.numeric_segment?(999)).to be true
    end

    it "returns true for string digits" do
      expect(helper.numeric_segment?("1")).to be true
      expect(helper.numeric_segment?("0")).to be true
      expect(helper.numeric_segment?("123")).to be true
    end

    it "returns false for non-numeric strings" do
      expect(helper.numeric_segment?("v")).to be false
      expect(helper.numeric_segment?("alpha")).to be false
      expect(helper.numeric_segment?("1a")).to be false
      expect(helper.numeric_segment?("a1")).to be false
    end

    it "returns false for nil" do
      expect(helper.numeric_segment?(nil)).to be false
    end

    it "returns false for other types" do
      expect(helper.numeric_segment?([])).to be false
      expect(helper.numeric_segment?({})).to be false
    end
  end

  describe "#to_integer" do
    it "returns integers as-is" do
      expect(helper.to_integer(1)).to eq(1)
      expect(helper.to_integer(0)).to eq(0)
      expect(helper.to_integer(999)).to eq(999)
    end

    it "converts string digits to integers" do
      expect(helper.to_integer("1")).to eq(1)
      expect(helper.to_integer("0")).to eq(0)
      expect(helper.to_integer("123")).to eq(123)
    end

    it "returns nil for non-numeric strings" do
      expect(helper.to_integer("v")).to be_nil
      expect(helper.to_integer("alpha")).to be_nil
      expect(helper.to_integer("1a")).to be_nil
    end

    it "returns nil for nil input" do
      expect(helper.to_integer(nil)).to be_nil
    end
  end

  describe "#classify_semver_update" do
    let(:prev_version) { instance_double("Version") }
    let(:curr_version) { instance_double("Version") }

    before do
      allow(prev_version).to receive(:respond_to?).with(:semver_parts).and_return(false)
      allow(prev_version).to receive(:respond_to?).with(:segments).and_return(true)
      allow(curr_version).to receive(:respond_to?).with(:semver_parts).and_return(false)
      allow(curr_version).to receive(:respond_to?).with(:segments).and_return(true)
      allow(Dependabot).to receive(:logger).and_return(instance_double(Logger, info: nil))
    end

    it "returns 'major' for major version bump" do
      allow(prev_version).to receive(:segments).and_return([1, 0, 0])
      allow(curr_version).to receive(:segments).and_return([2, 0, 0])

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end

    it "returns 'minor' for minor version bump" do
      allow(prev_version).to receive(:segments).and_return([1, 0, 0])
      allow(curr_version).to receive(:segments).and_return([1, 1, 0])

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("minor")
    end

    it "returns 'patch' for patch version bump" do
      allow(prev_version).to receive(:segments).and_return([1, 0, 0])
      allow(curr_version).to receive(:segments).and_return([1, 0, 1])

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("patch")
    end

    it "handles versions with 'v' prefix correctly" do
      allow(prev_version).to receive(:segments).and_return(["v", 1, 0, 0])
      allow(curr_version).to receive(:segments).and_return(["v", 2, 0, 0])

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end

    it "returns nil when versions cannot be parsed" do
      allow(prev_version).to receive(:segments).and_return(["alpha"])
      allow(curr_version).to receive(:segments).and_return(["beta"])

      expect(helper.classify_semver_update(prev_version, curr_version)).to be_nil
    end
  end
end
