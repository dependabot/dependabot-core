# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/channel"

RSpec.describe Dependabot::RustToolchain::Channel do
  describe "#initialize" do
    it "creates a channel with version" do
      channel = described_class.new(version: "1.72.0")
      expect(channel.version).to eq("1.72.0")
      expect(channel.channel).to be_nil
      expect(channel.date).to be_nil
    end

    it "creates a channel with channel name" do
      channel = described_class.new(channel: "stable")
      expect(channel.channel).to eq("stable")
      expect(channel.version).to be_nil
      expect(channel.date).to be_nil
    end

    it "creates a channel with channel and date" do
      channel = described_class.new(channel: "nightly", date: "2020-12-31")
      expect(channel.channel).to eq("nightly")
      expect(channel.date).to eq("2020-12-31")
      expect(channel.version).to be_nil
    end
  end

  describe ".from_parsed_data" do
    it "creates a channel from parser output" do
      parsed_data = { channel: "stable", date: nil, version: nil }
      channel = described_class.from_parsed_data(parsed_data)

      expect(channel.channel).to eq("stable")
      expect(channel.date).to be_nil
      expect(channel.version).to be_nil
    end
  end

  describe "#channel_type" do
    it "returns :version for version channels" do
      channel = described_class.new(version: "1.72.0")
      expect(channel.channel_type).to eq(:version)
    end

    it "returns :dated_channel for channels with dates" do
      channel = described_class.new(channel: "nightly", date: "2020-12-31")
      expect(channel.channel_type).to eq(:dated_channel)
    end

    it "returns :channel for channels without dates" do
      channel = described_class.new(channel: "stable")
      expect(channel.channel_type).to eq(:channel)
    end

    it "returns :unknown for empty channels" do
      channel = described_class.new
      expect(channel.channel_type).to eq(:unknown)
    end
  end

  describe "#<=>" do
    context "when comparing versions" do
      it "compares semantic versions correctly" do
        v1 = described_class.new(version: "1.72.0")
        v2 = described_class.new(version: "1.73.0")
        v3 = described_class.new(version: "1.72.1")

        expect(v1 <=> v2).to eq(-1)
        expect(v2 <=> v1).to eq(1)
        expect(v1 <=> v3).to eq(-1)
        expect(v3 <=> v1).to eq(1)
        expect(v1 <=> v1).to eq(0)
      end

      it "handles versions with different numbers of parts" do
        v1 = described_class.new(version: "1.72")
        v2 = described_class.new(version: "1.72.0")

        expect(v1 <=> v2).to eq(0)
      end
    end

    context "when comparing channels" do
      it "compares channel stability correctly" do
        stable = described_class.new(channel: "stable")
        beta = described_class.new(channel: "beta")
        nightly = described_class.new(channel: "nightly")

        expect(stable <=> beta).to eq(1)
        expect(beta <=> nightly).to eq(1)
        expect(stable <=> nightly).to eq(1)
        expect(nightly <=> stable).to eq(-1)
      end
    end

    context "when comparing dated channels" do
      it "compares by channel first, then by date" do
        stable1 = described_class.new(channel: "stable", date: "2020-12-31")
        stable2 = described_class.new(channel: "stable", date: "2021-01-01")
        beta1 = described_class.new(channel: "beta", date: "2021-12-31")

        expect(stable1 <=> stable2).to eq(-1)
        expect(stable2 <=> stable1).to eq(1)
        expect(stable1 <=> beta1).to eq(1) # stable > beta regardless of date
      end
    end

    context "when comparing different types" do
      it "returns nil when comparing different channel types" do
        version = described_class.new(version: "1.72.0")
        channel = described_class.new(channel: "stable")

        expect(version <=> channel).to be_nil
        expect(channel <=> version).to be_nil
      end

      it "returns nil when comparing with non-Channel objects" do
        channel = described_class.new(version: "1.72.0")
        expect(channel <=> "not a channel").to be_nil
      end
    end
  end

  describe "#==" do
    it "returns true for identical channels" do
      channel1 = described_class.new(version: "1.72.0")
      channel2 = described_class.new(version: "1.72.0")

      expect(channel1 == channel2).to be true
    end

    it "returns false for different channels" do
      channel1 = described_class.new(version: "1.72.0")
      channel2 = described_class.new(version: "1.73.0")

      expect(channel1 == channel2).to be false
    end

    it "returns false when comparing with non-Channel objects" do
      channel = described_class.new(version: "1.72.0")
      expect(channel == "1.72.0").to be false
    end
  end

  describe "#to_s" do
    it "returns version for version channels" do
      channel = described_class.new(version: "1.72.0")
      expect(channel.to_s).to eq("1.72.0")
    end

    it "returns channel-date for dated channels" do
      channel = described_class.new(channel: "nightly", date: "2020-12-31")
      expect(channel.to_s).to eq("nightly-2020-12-31")
    end

    it "returns channel name for channel-only" do
      channel = described_class.new(channel: "stable")
      expect(channel.to_s).to eq("stable")
    end

    it "returns 'unknown' for empty channels" do
      channel = described_class.new
      expect(channel.to_s).to eq("unknown")
    end
  end

  describe "integration with Comparable" do
    it "supports sorting" do
      channels = [
        described_class.new(version: "1.73.0"),
        described_class.new(version: "1.72.0"),
        described_class.new(version: "1.72.1")
      ]

      sorted = channels.sort
      expect(sorted.map(&:version)).to eq(["1.72.0", "1.72.1", "1.73.0"])
    end

    it "supports comparison operators" do
      v1 = described_class.new(version: "1.72.0")
      v2 = described_class.new(version: "1.73.0")

      expect(v1 < v2).to be true
      expect(v2 > v1).to be true
      expect(v1 <= v2).to be true
      expect(v2 >= v1).to be true
    end
  end
end
