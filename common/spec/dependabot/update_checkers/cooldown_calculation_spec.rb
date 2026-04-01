# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::UpdateCheckers::CooldownCalculation do
  describe ".within_cooldown_window?" do
    it "returns true when release is within the cooldown window" do
      release_date = Time.now - (12 * 60 * 60) # 12 hours ago
      expect(described_class.within_cooldown_window?(release_date, 1)).to be true
    end

    it "returns false when release is outside the cooldown window" do
      release_date = Time.now - (48 * 60 * 60) # 48 hours ago
      expect(described_class.within_cooldown_window?(release_date, 1)).to be false
    end

    it "returns false when cooldown_days is zero" do
      release_date = Time.now - 1 # 1 second ago
      expect(described_class.within_cooldown_window?(release_date, 0)).to be false
    end
  end

  describe ".cooldown_days_for" do
    let(:cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 5,
        semver_major_days: 14,
        semver_minor_days: 7,
        semver_patch_days: 2
      )
    end

    let(:version_class) do
      Class.new(Dependabot::Version) do
        def self.correct?(version)
          !version.nil? && version.match?(/^\d+(\.\d+)*$/)
        end
      end
    end

    it "returns major days for a major bump" do
      current = version_class.new("1.0.0")
      new_ver = version_class.new("2.0.0")
      expect(described_class.cooldown_days_for(cooldown, current, new_ver)).to eq(14)
    end

    it "returns minor days for a minor bump" do
      current = version_class.new("1.0.0")
      new_ver = version_class.new("1.1.0")
      expect(described_class.cooldown_days_for(cooldown, current, new_ver)).to eq(7)
    end

    it "returns patch days for a patch bump" do
      current = version_class.new("1.0.0")
      new_ver = version_class.new("1.0.1")
      expect(described_class.cooldown_days_for(cooldown, current, new_ver)).to eq(2)
    end

    it "returns default days when current version is nil" do
      new_ver = version_class.new("1.0.0")
      expect(described_class.cooldown_days_for(cooldown, nil, new_ver)).to eq(5)
    end
  end

  describe ".skip_cooldown?" do
    let(:cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(default_days: 1)
    end

    it "returns true when cooldown is nil" do
      expect(described_class.skip_cooldown?(nil, "my-dep")).to be true
    end

    it "returns true when cooldown is disabled" do
      expect(described_class.skip_cooldown?(cooldown, "my-dep", cooldown_enabled: false)).to be true
    end

    it "returns true when dependency is not included" do
      cooldown_with_include = Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 1,
        include: ["other-dep"]
      )
      expect(described_class.skip_cooldown?(cooldown_with_include, "my-dep")).to be true
    end

    it "returns false when all conditions are met" do
      expect(described_class.skip_cooldown?(cooldown, "my-dep", cooldown_enabled: true)).to be false
    end
  end
end
