# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/requirement"

RSpec.describe Dependabot::NpmAndYarn::Requirement do
  describe ".parse_dep_string" do
    context "with a simple exact version" do
      it "parses eslint@4.15.0" do
        result = described_class.parse_dep_string("eslint@4.15.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:normalised_name]).to eq("eslint")
        expect(result[:version]).to eq("4.15.0")
        expect(result[:requirement]).to eq("4.15.0")
        expect(result[:extras]).to be_nil
      end

      it "parses a hyphenated package name" do
        result = described_class.parse_dep_string("eslint-config-google@0.7.1")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint-config-google")
        expect(result[:version]).to eq("0.7.1")
        expect(result[:requirement]).to eq("0.7.1")
      end
    end

    context "with a scoped package" do
      it "parses @scope/package@version" do
        result = described_class.parse_dep_string("@babel/core@7.0.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("@babel/core")
        expect(result[:normalised_name]).to eq("@babel/core")
        expect(result[:version]).to eq("7.0.0")
        expect(result[:requirement]).to eq("7.0.0")
      end

      it "parses @prettier/plugin-xml@3.2.0" do
        result = described_class.parse_dep_string("@prettier/plugin-xml@3.2.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("@prettier/plugin-xml")
        expect(result[:version]).to eq("3.2.0")
      end
    end

    context "with range operators" do
      it "parses caret range ^4.15.0" do
        result = described_class.parse_dep_string("eslint@^4.15.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:version]).to eq("4.15.0")
        expect(result[:requirement]).to eq("^4.15.0")
      end

      it "parses tilde range ~5.3.0" do
        result = described_class.parse_dep_string("typescript@~5.3.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("typescript")
        expect(result[:version]).to eq("5.3.0")
        expect(result[:requirement]).to eq("~5.3.0")
      end

      it "parses >= range" do
        result = described_class.parse_dep_string("eslint@>=4.0.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:version]).to eq("4.0.0")
        expect(result[:requirement]).to eq(">=4.0.0")
      end

      it "parses > range" do
        result = described_class.parse_dep_string("eslint@>4.0.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:version]).to eq("4.0.0")
        expect(result[:requirement]).to eq(">4.0.0")
      end
    end

    context "with pre-release versions" do
      it "parses a pre-release version" do
        result = described_class.parse_dep_string("typescript@5.4.0-beta.1")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("typescript")
        expect(result[:version]).to eq("5.4.0-beta.1")
        expect(result[:requirement]).to eq("5.4.0-beta.1")
      end
    end

    context "with bare package name (no version)" do
      it "returns nil for eslint with no version" do
        result = described_class.parse_dep_string("eslint")
        expect(result).to be_nil
      end

      it "returns nil for scoped package with no version" do
        result = described_class.parse_dep_string("@babel/core")
        expect(result).to be_nil
      end
    end

    context "with non-numeric version specs" do
      it "returns nil version for a dist tag" do
        result = described_class.parse_dep_string("eslint@latest")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:version]).to be_nil
        expect(result[:requirement]).to eq("latest")
      end

      it "returns nil version for star range" do
        result = described_class.parse_dep_string("eslint@*")
        expect(result).not_to be_nil
        expect(result[:version]).to be_nil
        expect(result[:requirement]).to eq("*")
      end
    end

    context "with whitespace" do
      it "trims leading/trailing whitespace" do
        result = described_class.parse_dep_string("  eslint@4.15.0  ")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("eslint")
        expect(result[:version]).to eq("4.15.0")
      end
    end

    context "with empty or invalid input" do
      it "returns nil for empty string" do
        result = described_class.parse_dep_string("")
        expect(result).to be_nil
      end

      it "returns nil for whitespace-only string" do
        result = described_class.parse_dep_string("   ")
        expect(result).to be_nil
      end
    end
  end
end
