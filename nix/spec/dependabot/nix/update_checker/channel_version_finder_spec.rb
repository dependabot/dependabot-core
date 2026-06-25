# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/update_checker/channel_version_finder"

RSpec.describe Dependabot::Nix::UpdateChecker::ChannelVersionFinder do
  subject(:finder) do
    described_class.new(
      current_channel: current_channel,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:listing_url) { "https://channels.nixos.org/" }

  let(:channel_listing) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
        <Name>nix-channels</Name>
        <Prefix>nixos-</Prefix>
        <Contents><Key>nixos-24.11</Key><LastModified>2025-07-01T03:39:48.000Z</LastModified></Contents>
        <Contents><Key>nixos-24.11-small</Key><LastModified>2025-07-01T11:45:13.000Z</LastModified></Contents>
        <Contents><Key>nixos-25.05</Key><LastModified>2026-01-06T15:37:21.000Z</LastModified></Contents>
        <Contents><Key>nixos-25.05-small</Key><LastModified>2026-01-03T10:42:03.000Z</LastModified></Contents>
        <Contents><Key>nixos-26.05</Key><LastModified>2026-06-22T23:44:27.000Z</LastModified></Contents>
        <Contents><Key>nixos-26.05-small</Key><LastModified>2026-06-24T20:46:42.000Z</LastModified></Contents>
        <Contents><Key>nixos-unstable</Key><LastModified>2026-06-16T15:10:41.000Z</LastModified></Contents>
      </ListBucketResult>
    XML
  end

  describe "#latest_channel" do
    context "with a versioned channel that has newer releases" do
      let(:current_channel) { "nixos-25.05" }

      before do
        stub_request(:get, listing_url)
          .with(query: hash_including("prefix" => "nixos-"))
          .to_return(status: 200, body: channel_listing)
        stub_request(:get, "https://channels.nixos.org/nixos-26.05/git-revision")
          .to_return(status: 200, body: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca")
      end

      it "returns the newest same-family channel and its revision" do
        expect(finder.latest_channel).to eq(
          channel: "nixos-26.05",
          url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
          commit_sha: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca"
        )
      end

      it "does not cross into the -small family" do
        finder.latest_channel
        expect(WebMock)
          .not_to have_requested(:get, "https://channels.nixos.org/nixos-26.05-small/git-revision")
      end
    end

    context "when already on the newest channel" do
      let(:current_channel) { "nixos-26.05" }

      before do
        stub_request(:get, listing_url)
          .with(query: hash_including("prefix" => "nixos-"))
          .to_return(status: 200, body: channel_listing)
      end

      it "returns nil" do
        expect(finder.latest_channel).to be_nil
      end
    end

    context "with a rolling (unstable) channel" do
      let(:current_channel) { "nixos-unstable" }

      it "returns nil without listing channels" do
        expect(finder.latest_channel).to be_nil
        expect(WebMock).not_to have_requested(:get, listing_url)
      end
    end

    context "when the only newer channel is ignored" do
      let(:current_channel) { "nixos-25.05" }
      let(:ignored_versions) { ["= 26.05"] }

      before do
        stub_request(:get, listing_url)
          .with(query: hash_including("prefix" => "nixos-"))
          .to_return(status: 200, body: channel_listing)
      end

      it "returns nil" do
        expect(finder.latest_channel).to be_nil
      end
    end

    context "when the candidate revision cannot be resolved" do
      let(:current_channel) { "nixos-25.05" }

      before do
        stub_request(:get, listing_url)
          .with(query: hash_including("prefix" => "nixos-"))
          .to_return(status: 200, body: channel_listing)
        stub_request(:get, "https://channels.nixos.org/nixos-26.05/git-revision")
          .to_return(status: 404, body: "")
      end

      it "returns nil" do
        expect(finder.latest_channel).to be_nil
      end
    end

    context "when listing the channels fails" do
      let(:current_channel) { "nixos-25.05" }

      before do
        stub_request(:get, listing_url)
          .with(query: hash_including("prefix" => "nixos-"))
          .to_return(status: 500, body: "")
      end

      it "returns nil" do
        expect(finder.latest_channel).to be_nil
      end
    end
  end

  describe "#current_channel_revision" do
    let(:current_channel) { "nixos-26.05" }

    before do
      stub_request(:get, "https://channels.nixos.org/nixos-26.05/git-revision")
        .to_return(status: 200, body: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca\n")
    end

    it "resolves the current channel revision, trimming whitespace" do
      expect(finder.current_channel_revision).to eq("bd0ff2d3eac24699c3664d5966b9ef36f388e2ca")
    end

    context "when the response is not a valid revision" do
      before do
        stub_request(:get, "https://channels.nixos.org/nixos-26.05/git-revision")
          .to_return(status: 200, body: "not-a-sha")
      end

      it "returns nil" do
        expect(finder.current_channel_revision).to be_nil
      end
    end
  end
end
