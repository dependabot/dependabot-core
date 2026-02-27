# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/requirement"

RSpec.describe Dependabot::Cargo::Requirement, ".parse_dep_string" do
  subject(:result) { described_class.parse_dep_string(dep_string) }

  context "with a simple name:version string" do
    let(:dep_string) { "serde:1.0.193" }

    it "parses the name and version" do
      expect(result).to eq(
        name: "serde",
        normalised_name: "serde",
        version: "1.0.193",
        requirement: "1.0.193",
        extras: nil
      )
    end
  end

  context "with a CLI dependency" do
    let(:dep_string) { "cli:rustfmt-nightly:1.6.0" }

    it "strips the cli prefix and sets extras" do
      expect(result).to eq(
        name: "rustfmt-nightly",
        normalised_name: "rustfmt-nightly",
        version: "1.6.0",
        requirement: "1.6.0",
        extras: "cli"
      )
    end
  end

  context "with a tilde requirement" do
    let(:dep_string) { "anyhow:~1.0.0" }

    it "parses the tilde constraint" do
      expect(result).to eq(
        name: "anyhow",
        normalised_name: "anyhow",
        version: "1.0.0",
        requirement: "~1.0.0",
        extras: nil
      )
    end
  end

  context "with a caret requirement" do
    let(:dep_string) { "clap:^4.4.0" }

    it "parses the caret constraint" do
      expect(result).to eq(
        name: "clap",
        normalised_name: "clap",
        version: "4.4.0",
        requirement: "^4.4.0",
        extras: nil
      )
    end
  end

  context "with a >= requirement" do
    let(:dep_string) { "tokio:>=1.35.0" }

    it "parses the >= constraint" do
      expect(result).to eq(
        name: "tokio",
        normalised_name: "tokio",
        version: "1.35.0",
        requirement: ">=1.35.0",
        extras: nil
      )
    end
  end

  context "with a pre-release version" do
    let(:dep_string) { "nightly-tools:0.1.0-alpha.1" }

    it "parses the pre-release version" do
      expect(result).to eq(
        name: "nightly-tools",
        normalised_name: "nightly-tools",
        version: "0.1.0-alpha.1",
        requirement: "0.1.0-alpha.1",
        extras: nil
      )
    end
  end

  context "with an empty string" do
    let(:dep_string) { "" }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with only whitespace" do
    let(:dep_string) { "   " }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with no version (just a name)" do
    let(:dep_string) { "serde" }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with cli prefix but no version" do
    let(:dep_string) { "cli:rustfmt" }

    it "returns nil since only two parts with cli prefix means no version" do
      expect(result).to be_nil
    end
  end

  context "with name:version with leading/trailing whitespace" do
    let(:dep_string) { "  serde : 1.0.193  " }

    it "strips whitespace" do
      expect(result).to eq(
        name: "serde ",
        normalised_name: "serde ",
        version: "1.0.193",
        requirement: "1.0.193",
        extras: nil
      )
    end
  end

  context "with a CLI dependency with uppercase CLI prefix" do
    let(:dep_string) { "CLI:cargo-clippy:0.1.75" }

    it "handles case-insensitive cli prefix" do
      expect(result).to eq(
        name: "cargo-clippy",
        normalised_name: "cargo-clippy",
        version: "0.1.75",
        requirement: "0.1.75",
        extras: "cli"
      )
    end
  end
end
