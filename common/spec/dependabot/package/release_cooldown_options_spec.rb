# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Package::ReleaseCooldownOptions do
  subject(:release_cooldown_options) do
    described_class.new(
      default_days: default_days,
      major_days: major_days,
      minor_days: minor_days,
      patch_days: patch_days,
      include: include_list,
      exclude: exclude_list
    )
  end

  let(:default_days) { 7 }
  let(:major_days) { 10 }
  let(:minor_days) { 5 }
  let(:patch_days) { 2 }
  let(:include_list) { ["*", "package-a"] }
  let(:exclude_list) { ["package-b"] }

  describe "#major_days" do
    it "returns major_days when set" do
      expect(release_cooldown_options.major_days).to eq(10)
    end

    context "when major_days is zero" do
      let(:major_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.major_days).to eq(7)
      end
    end
  end

  describe "#minor_days" do
    it "returns minor_days when set" do
      expect(release_cooldown_options.minor_days).to eq(5)
    end

    context "when minor_days is zero" do
      let(:minor_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.minor_days).to eq(7)
      end
    end
  end

  describe "#patch_days" do
    it "returns patch_days when set" do
      expect(release_cooldown_options.patch_days).to eq(2)
    end

    context "when patch_days is zero" do
      let(:patch_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.patch_days).to eq(7)
      end
    end
  end

  describe "#included?" do
    context "when include is set to ['*']" do
      let(:include_list) { ["*"] }

      it "returns true if the dependency is not in the exclude list" do
        expect(release_cooldown_options.included?("package-a")).to be true
      end

      it "returns false if the dependency is in the exclude list" do
        expect(release_cooldown_options.included?("package-b")).to be true
      end
    end

    context "when include is use a pattern" do
      let(:include_list) { ["package-*"] }

      it "returns true if the dependency is not in the exclude list" do
        expect(release_cooldown_options.included?("package-a")).to be true
      end

      it "returns false if the dependency is in the exclude list" do
        expect(release_cooldown_options.included?("package-b")).to be true
      end

      it "returns false if the dependency does not match the pattern" do
        expect(release_cooldown_options.included?("different-package")).to be false
      end
    end

    context "when the include list is not empty" do
      let(:include_list) { ["package-a"] }

      it "returns true if the dependency is in the include list" do
        expect(release_cooldown_options.included?("package-a")).to be true
      end

      it "returns false if the dependency is not in the include list" do
        expect(release_cooldown_options.included?("package-b")).to be false
      end
    end

    context "when the include list is empty" do
      let(:include_list) { [] }

      it "returns true if the dependency is not in the exclude list" do
        expect(release_cooldown_options.included?("package-a")).to be true
      end

      it "returns false if the dependency is in the exclude list" do
        expect(release_cooldown_options.included?("package-b")).to be true
      end
    end
  end

  describe "#excluded?" do
    it "returns true if the dependency is in the exclude list" do
      expect(release_cooldown_options.excluded?("package-b")).to be true
    end

    it "returns false if the dependency is not in the exclude list" do
      expect(release_cooldown_options.excluded?("package-c")).to be false
    end
  end
end
