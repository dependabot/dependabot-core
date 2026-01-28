# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/rust_toolchain/models/rust_toolchain_toml"

RSpec.describe Dependabot::RustToolchain::Models::RustToolchainToml do
  describe ".from_toml" do
    context "with valid TOML" do
      let(:toml_content) do
        <<~TOML
          [toolchain]
          channel = "nightly-2020-07-10"
        TOML
      end

      it "parses the TOML and creates a valid struct" do
        result = described_class.from_toml(toml_content)

        expect(result.toolchain).not_to be_nil
        expect(result.toolchain.channel).to eq("nightly-2020-07-10")
      end
    end

    context "with empty toolchain section" do
      let(:toml_content) do
        <<~TOML
          [toolchain]
        TOML
      end

      it "raises DependencyFileNotParseable" do
        expect { described_class.from_toml(toml_content) }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with no toolchain section" do
      let(:toml_content) { "" }

      it "raises DependencyFileNotParseable" do
        expect { described_class.from_toml(toml_content) }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with invalid TOML syntax" do
      let(:invalid_toml) { "[toolchain\nchannel = \"stable\"" }

      it "raises DependencyFileNotParseable" do
        expect { described_class.from_toml(invalid_toml) }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
