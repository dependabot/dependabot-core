# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/channel_parser"

RSpec.describe Dependabot::RustToolchain::ChannelParser do
  describe "#parse" do
    subject(:parser) { described_class.new(channel) }

    context "with a specific version" do
      context "with major and minor version" do
        let(:channel) { "1.72" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to be_nil
          expect(result.date).to be_nil
          expect(result.version).to eq("1.72")
        end
      end

      context "with major, minor, and patch version" do
        let(:channel) { "1.72.0" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to be_nil
          expect(result.date).to be_nil
          expect(result.version).to eq("1.72.0")
        end
      end
    end

    context "with a channel and date" do
      context "with nightly channel" do
        let(:channel) { "nightly-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("nightly")
          expect(result.date).to eq("2020-12-31")
          expect(result.version).to be_nil
        end
      end

      context "with beta channel" do
        let(:channel) { "beta-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("beta")
          expect(result.date).to eq("2020-12-31")
          expect(result.version).to be_nil
        end
      end

      context "with stable channel" do
        let(:channel) { "stable-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("stable")
          expect(result.date).to eq("2020-12-31")
          expect(result.version).to be_nil
        end
      end
    end

    context "with a channel only" do
      context "with nightly channel" do
        let(:channel) { "nightly" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("nightly")
          expect(result.date).to be_nil
          expect(result.version).to be_nil
        end
      end

      context "with beta channel" do
        let(:channel) { "beta" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("beta")
          expect(result.date).to be_nil
          expect(result.version).to be_nil
        end
      end

      context "with stable channel" do
        let(:channel) { "stable" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result.stability).to eq("stable")
          expect(result.date).to be_nil
          expect(result.version).to be_nil
        end
      end
    end

    context "with invalid format" do
      let(:channel) { "invalid-format" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end

    context "with empty string" do
      let(:channel) { "" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end
  end
end
