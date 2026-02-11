# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/requirement"

RSpec.describe Dependabot::Julia::Requirement, ".parse_dep_string" do
  subject(:result) { described_class.parse_dep_string(dep_string) }

  context "with a simple package@version" do
    let(:dep_string) { "JSON@0.21.4" }

    it "parses name and version" do
      expect(result).to eq({
        name: "JSON",
        normalised_name: "JSON",
        version: "0.21.4",
        requirement: "0.21.4",
        extras: nil
      })
    end
  end

  context "with a two-part version" do
    let(:dep_string) { "ExtraDepA@1" }

    it "parses the version correctly" do
      expect(result[:name]).to eq("ExtraDepA")
      expect(result[:version]).to eq("1")
      expect(result[:requirement]).to eq("1")
    end
  end

  context "with a two-segment version" do
    let(:dep_string) { "ExtraDepB@2.4" }

    it "parses the version correctly" do
      expect(result[:name]).to eq("ExtraDepB")
      expect(result[:version]).to eq("2.4")
      expect(result[:requirement]).to eq("2.4")
    end
  end

  context "with a caret constraint" do
    let(:dep_string) { "JuliaFormatter@^1.0.0" }

    it "parses with caret preserved in requirement" do
      expect(result[:name]).to eq("JuliaFormatter")
      expect(result[:version]).to eq("1.0.0")
      expect(result[:requirement]).to eq("^1.0.0")
    end
  end

  context "with a tilde constraint" do
    let(:dep_string) { "CSTParser@~3.3.0" }

    it "parses with tilde preserved in requirement" do
      expect(result[:name]).to eq("CSTParser")
      expect(result[:version]).to eq("3.3.0")
      expect(result[:requirement]).to eq("~3.3.0")
    end
  end

  context "with >= constraint" do
    let(:dep_string) { "HTTP@>=1.5.0" }

    it "parses with operator preserved" do
      expect(result[:name]).to eq("HTTP")
      expect(result[:version]).to eq("1.5.0")
      expect(result[:requirement]).to eq(">=1.5.0")
    end
  end

  context "with an empty string" do
    let(:dep_string) { "" }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with whitespace only" do
    let(:dep_string) { "   " }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with no @ separator" do
    let(:dep_string) { "JSON" }

    it "returns nil (no version)" do
      expect(result).to be_nil
    end
  end

  context "with an empty version after @" do
    let(:dep_string) { "JSON@" }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with whitespace around name and version" do
    let(:dep_string) { "  JSON @ 0.21.4  " }

    it "trims whitespace correctly" do
      expect(result[:name]).to eq("JSON")
      expect(result[:version]).to eq("0.21.4")
    end
  end

  context "with a v-prefixed version" do
    let(:dep_string) { "HTTP@v1.10.0" }

    it "parses the v-prefixed version" do
      expect(result[:name]).to eq("HTTP")
      expect(result[:version]).to eq("1.10.0")
      expect(result[:requirement]).to eq("v1.10.0")
    end
  end
end
