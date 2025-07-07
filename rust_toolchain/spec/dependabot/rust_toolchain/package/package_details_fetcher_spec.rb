# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/package/package_details_fetcher"

RSpec.describe Dependabot::RustToolchain::Package::PackageDetailsFetcher do
  subject(:finder) { described_class.new(dependency: dependency) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust-toolchain",
      version: "1.0.0",
      requirements: [],
      package_manager: "rust_toolchain"
    )
  end

  describe "#fetch" do
    let(:manifests_response) do
      <<~MANIFESTS
        static.rust-lang.org/dist/2018-05-10/channel-rust-stable.toml
        static.rust-lang.org/dist/2018-05-10/channel-rust-beta.toml
        static.rust-lang.org/dist/2018-05-10/channel-rust-nightly.toml
        static.rust-lang.org/dist/2018-05-10/channel-rust-1.26.0.toml
        static.rust-lang.org/dist/2018-05-11/channel-rust-stable.toml
        static.rust-lang.org/dist/2018-05-11/channel-rust-1.26.1.toml
        static.rust-lang.org/dist/2019-01-15/channel-rust-1.32.0.toml

        # This should be ignored (empty line)
        static.rust-lang.org/dist/2020-03-12/channel-rust-1.42.0.toml
      MANIFESTS
    end

    before do
      allow(Dependabot::RegistryClient).to receive(:get)
        .with(url: described_class::MANIFESTS_URL)
        .and_return(instance_double(Excon::Response, body: manifests_response))
    end

    it "fetches and parses all manifests correctly" do
      package_details = finder.fetch

      expect(package_details.releases).to be_an(Array)
      expect(package_details.releases.length).to eq(8)
    end

    it "parses stable channel versions correctly" do
      package_details = finder.fetch
      stable_releases = package_details.releases.select { |r| r.version.channel.stability == "stable" }

      expect(stable_releases.length).to eq(2)
      stable_channel = stable_releases.first.version.channel
      expect(stable_channel.stability).to eq("stable")
      expect(stable_channel.date).to eq("2018-05-11")
      expect(stable_channel.version).to be_nil
    end

    it "parses beta channel versions correctly" do
      package_details = finder.fetch
      beta_releases = package_details.releases.select { |r| r.version.channel.stability == "beta" }

      expect(beta_releases.length).to eq(1)
      beta_channel = beta_releases.first.version.channel
      expect(beta_channel.stability).to eq("beta")
      expect(beta_channel.date).to eq("2018-05-10")
      expect(beta_channel.version).to be_nil
    end

    it "parses nightly channel versions correctly" do
      package_details = finder.fetch
      nightly_releases = package_details.releases.select { |r| r.version.channel.stability == "nightly" }

      expect(nightly_releases.length).to eq(1)
      nightly_channel = nightly_releases.first.version.channel
      expect(nightly_channel.stability).to eq("nightly")
      expect(nightly_channel.date).to eq("2018-05-10")
      expect(nightly_channel.version).to be_nil
    end

    # rubocop:disable Naming/VariableNumber
    it "parses specific version releases correctly" do
      package_details = finder.fetch
      version_releases = package_details.releases.select do |r|
        channel = r.version.channel
        channel&.version && !channel&.stability
      end

      expect(version_releases.length).to eq(4)

      version_1_26_0 = version_releases.find do |v|
        v.version.channel&.version == "1.26.0"
      end
      channel_1_26_0 = version_1_26_0.version.channel
      expect(channel_1_26_0.version).to eq("1.26.0")
      expect(channel_1_26_0.date).to be_nil # Version releases don't have dates in the current implementation
      expect(channel_1_26_0.stability).to be_nil

      version_1_42_0 = version_releases.find do |v|
        v.version.channel&.version == "1.42.0"
      end
      channel_1_42_0 = version_1_42_0.version.channel
      expect(channel_1_42_0.version).to eq("1.42.0")
      expect(channel_1_42_0.date).to be_nil
      expect(channel_1_42_0.stability).to be_nil
    end
    # rubocop:enable Naming/VariableNumber

    it "handles network errors gracefully" do
      allow(Dependabot::RegistryClient).to receive(:get)
        .with(url: described_class::MANIFESTS_URL)
        .and_raise(Excon::Error::Timeout.new("Request timeout"))

      expect { finder.fetch }.to raise_error(Excon::Error::Timeout)
    end
  end

  describe "#parse_manifest_line" do
    it "parses stable channel manifest lines" do
      line = "static.rust-lang.org/dist/2018-05-10/channel-rust-stable.toml"
      version = finder.send(:parse_manifest_line, line)

      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("stable-2018-05-10")

      channel = version.channel
      expect(channel.stability).to eq("stable")
      expect(channel.date).to eq("2018-05-10")
      expect(channel.version).to be_nil
    end

    it "parses beta channel manifest lines" do
      line = "static.rust-lang.org/dist/2019-01-01/channel-rust-beta.toml"
      version = finder.send(:parse_manifest_line, line)

      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("beta-2019-01-01")

      channel = version.channel
      expect(channel.stability).to eq("beta")
      expect(channel.date).to eq("2019-01-01")
      expect(channel.version).to be_nil
    end

    it "parses nightly channel manifest lines" do
      line = "static.rust-lang.org/dist/2020-12-25/channel-rust-nightly.toml"
      version = finder.send(:parse_manifest_line, line)

      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("nightly-2020-12-25")

      channel = version.channel
      expect(channel.stability).to eq("nightly")
      expect(channel.date).to eq("2020-12-25")
      expect(channel.version).to be_nil
    end

    it "parses version-specific manifest lines" do
      line = "static.rust-lang.org/dist/2018-05-10/channel-rust-1.26.0.toml"
      version = finder.send(:parse_manifest_line, line)

      expect(version).to be_a(Dependabot::RustToolchain::Version)
      expect(version.to_s).to eq("1.26.0")

      channel = version.channel
      expect(channel.version).to eq("1.26.0")
      expect(channel.date).to be_nil
      expect(channel.stability).to be_nil
    end

    it "returns nil for invalid manifest lines" do
      invalid_lines = [
        "not-a-valid-manifest-line",
        "static.rust-lang.org/dist/invalid-date/channel-rust-stable.toml",
        "static.rust-lang.org/dist/2018-05-10/channel-rust-unknown.toml",
        "static.rust-lang.org/dist/2018-05-10/not-a-channel.toml"
      ]

      invalid_lines.each do |line|
        result = finder.send(:parse_manifest_line, line)
        expect(result).to be_nil, "Expected nil for line: #{line}"
      end
    end
  end
end
