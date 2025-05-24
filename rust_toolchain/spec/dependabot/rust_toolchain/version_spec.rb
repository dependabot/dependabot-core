# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/version"

RSpec.describe Dependabot::RustToolchain::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#initialize" do
    context "with a specific version string" do
      let(:version_string) { "1.72.0" }

      it "initializes successfully" do
        expect(version.to_s).to eq("1.72.0")
      end

      it "sets up the channel correctly" do
        channel = version.instance_variable_get(:@channel)
        expect(channel).not_to be_nil
        expect(channel.version).to eq("1.72.0")
        expect(channel.channel).to be_nil
        expect(channel.date).to be_nil
      end
    end

    context "with a channel string" do
      let(:version_string) { "stable" }

      it "initializes successfully" do
        expect(version.to_s).to eq("stable")
      end

      it "sets up the channel correctly" do
        channel = version.instance_variable_get(:@channel)
        expect(channel).not_to be_nil
        expect(channel.channel).to eq("stable")
        expect(channel.version).to be_nil
        expect(channel.date).to be_nil
      end
    end

    context "with a dated channel string" do
      let(:version_string) { "nightly-2023-12-25" }

      it "initializes successfully" do
        expect(version.to_s).to eq("nightly-2023-12-25")
      end

      it "sets up the channel correctly" do
        channel = version.instance_variable_get(:@channel)
        expect(channel).not_to be_nil
        expect(channel.channel).to eq("nightly")
        expect(channel.date).to eq("2023-12-25")
        expect(channel.version).to be_nil
      end
    end

    context "with nil version" do
      let(:version_string) { nil }

      it "raises BadRequirementError" do
        expect { version }.to raise_error(Dependabot::BadRequirementError, "Malformed channel string - string is nil")
      end
    end

    context "with invalid version string" do
      let(:version_string) { "invalid-format" }

      it "raises ArgumentError" do
        expect { version }.to raise_error(ArgumentError, "Malformed version number string invalid-format")
      end
    end
  end

  describe ".new" do
    it "returns a Dependabot::RustToolchain::Version instance" do
      result = described_class.new("1.72.0")
      expect(result).to be_a(described_class)
    end
  end

  describe ".correct?" do
    context "with valid version strings" do
      it "returns true for semantic versions" do
        expect(described_class.correct?("1.72.0")).to be true
        expect(described_class.correct?("1.72")).to be true
      end

      it "returns true for channel names" do
        expect(described_class.correct?("stable")).to be true
        expect(described_class.correct?("beta")).to be true
        expect(described_class.correct?("nightly")).to be true
      end

      it "returns true for dated channels" do
        expect(described_class.correct?("stable-2023-12-25")).to be true
        expect(described_class.correct?("beta-2023-12-25")).to be true
        expect(described_class.correct?("nightly-2023-12-25")).to be true
      end
    end

    context "with invalid version strings" do
      it "returns false for empty string" do
        expect(described_class.correct?("")).to be false
      end

      it "returns false for invalid formats" do
        expect(described_class.correct?("invalid-format")).to be false
        expect(described_class.correct?("1.2.3.4")).to be false
        expect(described_class.correct?("unknown-channel")).to be false
      end
    end

    context "when ArgumentError is raised" do
      it "returns false and logs the error" do
        allow(Dependabot::RustToolchain::ChannelParser).to receive(:new).and_raise(ArgumentError, "test error")
        allow(Dependabot.logger).to receive(:info)

        result = described_class.correct?("test")

        expect(result).to be false
        expect(Dependabot.logger).to have_received(:info).with("Malformed version string test")
      end
    end
  end

  describe "#to_s" do
    context "with version channel" do
      let(:version_string) { "1.72.0" }

      it "returns the version string" do
        expect(version.to_s).to eq("1.72.0")
      end
    end

    context "with channel only" do
      let(:version_string) { "stable" }

      it "returns the channel name" do
        expect(version.to_s).to eq("stable")
      end
    end

    context "with dated channel" do
      let(:version_string) { "nightly-2023-12-25" }

      it "returns the channel with date" do
        expect(version.to_s).to eq("nightly-2023-12-25")
      end
    end
  end

  describe "edge cases" do
    context "with version containing extra whitespace" do
      let(:version_string) { " stable " }

      it "handles whitespace gracefully" do
        # The parser should handle or reject this appropriately
        result = version.to_s
        expect(result).to be_a(String)
      end
    end
  end

  describe "utility registration" do
    it "registers with Dependabot::Utils" do
      # This verifies the registration at the bottom of the file works
      expect(Dependabot::Utils.version_class_for_package_manager("rust_toolchain")).to eq(described_class)
    end
  end
end
