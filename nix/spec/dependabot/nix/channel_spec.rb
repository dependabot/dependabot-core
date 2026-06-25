# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/channel"

RSpec.describe Dependabot::Nix::Channel do
  describe ".channel_url?" do
    it "recognises NixOS channel tarball URLs" do
      expect(described_class.channel_url?("https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz"))
        .to be(true)
    end

    it "rejects the resolved releases URL" do
      url = "https://releases.nixos.org/nixos/26.05/nixos-26.05.1550.bd0ff2d3eac2/nixexprs.tar.xz"
      expect(described_class.channel_url?(url)).to be(false)
    end

    it "rejects unrelated tarball URLs" do
      expect(described_class.channel_url?("https://example.com/archive/v1.0.0.tar.gz")).to be(false)
    end

    it "handles nil" do
      expect(described_class.channel_url?(nil)).to be(false)
    end
  end

  describe ".channel_name_from_url" do
    it "extracts the channel segment" do
      expect(described_class.channel_name_from_url("https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz"))
        .to eq("nixos-26.05")
    end

    it "returns nil for non-channel URLs" do
      expect(described_class.channel_name_from_url("https://example.com/foo.tar.gz")).to be_nil
    end
  end

  describe ".url_for" do
    it "builds the channel tarball URL" do
      expect(described_class.url_for("nixos-26.05"))
        .to eq("https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz")
    end
  end

  describe "version parsing (inherited from VersionedName)" do
    it "exposes the channel name's version and family via the shared base" do
      channel = described_class.new("nixos-26.05")
      expect(channel.versioned?).to be(true)
      expect(channel.same_family?(described_class.new("nixos-25.05"))).to be(true)
    end
  end
end
