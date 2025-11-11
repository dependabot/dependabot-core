# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/models/rust_toolchain_config"

RSpec.describe Dependabot::RustToolchain::Models::RustToolchainConfig do
  describe ".from_hash" do
    context "with channel specified" do
      let(:config_hash) do
        {
          "channel" => "nightly-2020-07-10"
        }
      end

      it "creates a config with channel populated" do
        result = described_class.from_hash(config_hash)

        expect(result.channel).to eq("nightly-2020-07-10")
      end
    end

    context "with empty hash" do
      let(:config_hash) { {} }

      it "raises DependencyFileNotParseable" do
        expect { described_class.from_hash(config_hash) }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
