# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_parser/toolchain_channel_parser"

RSpec.describe Dependabot::Cargo::FileParser::ToolchainChannelParser do
  describe "#parse" do
    subject(:parser) { described_class.new(toolchain) }

    context "with a specific version" do
      context "with major and minor version" do
        let(:toolchain) { "1.72" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to be_nil
          expect(result[:date]).to be_nil
          expect(result[:version]).to eq("1.72")
        end
      end

      context "with major, minor, and patch version" do
        let(:toolchain) { "1.72.0" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to be_nil
          expect(result[:date]).to be_nil
          expect(result[:version]).to eq("1.72.0")
        end
      end
    end

    context "with a channel and date" do
      context "with nightly channel" do
        let(:toolchain) { "nightly-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("nightly")
          expect(result[:date]).to eq("2020-12-31")
          expect(result[:version]).to be_nil
        end
      end

      context "with beta channel" do
        let(:toolchain) { "beta-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("beta")
          expect(result[:date]).to eq("2020-12-31")
          expect(result[:version]).to be_nil
        end
      end

      context "with stable channel" do
        let(:toolchain) { "stable-2020-12-31" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("stable")
          expect(result[:date]).to eq("2020-12-31")
          expect(result[:version]).to be_nil
        end
      end
    end

    context "with a channel only" do
      context "with nightly channel" do
        let(:toolchain) { "nightly" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("nightly")
          expect(result[:date]).to be_nil
          expect(result[:version]).to be_nil
        end
      end

      context "with beta channel" do
        let(:toolchain) { "beta" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("beta")
          expect(result[:date]).to be_nil
          expect(result[:version]).to be_nil
        end
      end

      context "with stable channel" do
        let(:toolchain) { "stable" }

        it "returns the correct toolchain channel details" do
          result = parser.parse
          expect(result[:channel]).to eq("stable")
          expect(result[:date]).to be_nil
          expect(result[:version]).to be_nil
        end
      end
    end

    context "with invalid format" do
      let(:toolchain) { "invalid-format" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end

    context "with empty string" do
      let(:toolchain) { "" }

      it "returns nil" do
        expect(parser.parse).to be_nil
      end
    end
  end
end
