# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/requirement"

RSpec.describe Dependabot::Bundler::Requirement do
  describe ".parse_dep_string" do
    context "with a simple exact version" do
      it "parses scss_lint:0.52.0" do
        result = described_class.parse_dep_string("scss_lint:0.52.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("scss_lint")
        expect(result[:normalised_name]).to eq("scss_lint")
        expect(result[:version]).to eq("0.52.0")
        expect(result[:requirement]).to eq("0.52.0")
        expect(result[:extras]).to be_nil
      end

      it "parses a hyphenated gem name" do
        result = described_class.parse_dep_string("rubocop-rails:2.19.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rubocop-rails")
        expect(result[:version]).to eq("2.19.0")
        expect(result[:requirement]).to eq("2.19.0")
      end
    end

    context "with range operators" do
      it "parses pessimistic version operator ~> 1.50" do
        result = described_class.parse_dep_string("rubocop:~> 1.50")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rubocop")
        expect(result[:version]).to eq("1.50")
        expect(result[:requirement]).to eq("~> 1.50")
      end

      it "parses greater than or equal >= 1.0" do
        result = described_class.parse_dep_string("rubocop:>= 1.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rubocop")
        expect(result[:version]).to eq("1.0")
        expect(result[:requirement]).to eq(">= 1.0")
      end

      it "parses exact version constraint = 1.50.0" do
        result = described_class.parse_dep_string("rubocop:= 1.50.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rubocop")
        expect(result[:version]).to eq("1.50.0")
        expect(result[:requirement]).to eq("= 1.50.0")
      end

      it "parses greater than > 1.0" do
        result = described_class.parse_dep_string("rails:> 6.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rails")
        expect(result[:version]).to eq("6.0")
        expect(result[:requirement]).to eq("> 6.0")
      end

      it "parses less than or equal <= 2.0" do
        result = described_class.parse_dep_string("rails:<= 7.0")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rails")
        expect(result[:version]).to eq("7.0")
        expect(result[:requirement]).to eq("<= 7.0")
      end
    end

    context "with pre-release versions" do
      it "parses pre-release version with alpha suffix" do
        result = described_class.parse_dep_string("rails:7.0.0.alpha1")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rails")
        expect(result[:version]).to eq("7.0.0.alpha1")
        expect(result[:requirement]).to eq("7.0.0.alpha1")
      end

      it "parses pre-release version with rc suffix" do
        result = described_class.parse_dep_string("rails:7.0.0.rc1")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rails")
        expect(result[:version]).to eq("7.0.0.rc1")
        expect(result[:requirement]).to eq("7.0.0.rc1")
      end
    end

    context "with no version" do
      it "returns nil for gem name without version" do
        result = described_class.parse_dep_string("rubocop")
        expect(result).to be_nil
      end

      it "returns nil for gem name with just colon" do
        result = described_class.parse_dep_string("rubocop:")
        expect(result).to be_nil
      end
    end

    context "with whitespace" do
      it "handles leading and trailing whitespace" do
        result = described_class.parse_dep_string("  scss_lint:0.52.0  ")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("scss_lint")
        expect(result[:version]).to eq("0.52.0")
      end

      it "handles whitespace in version constraint" do
        result = described_class.parse_dep_string("rubocop:~>  1.50")
        expect(result).not_to be_nil
        expect(result[:name]).to eq("rubocop")
        expect(result[:version]).to eq("1.50")
        expect(result[:requirement]).to eq("~>  1.50")
      end
    end

    context "with invalid input" do
      it "returns nil for empty string" do
        result = described_class.parse_dep_string("")
        expect(result).to be_nil
      end

      it "returns nil for whitespace only" do
        result = described_class.parse_dep_string("   ")
        expect(result).to be_nil
      end

      it "returns nil for @ format (not colon)" do
        result = described_class.parse_dep_string("rubocop@1.50.0")
        expect(result).to be_nil
      end
    end
  end
end
