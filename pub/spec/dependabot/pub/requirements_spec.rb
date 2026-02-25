# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/requirement"

RSpec.describe Dependabot::Pub::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a blank string" do
      let(:requirement_string) { "" }

      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    context "with a pre-release" do
      let(:requirement_string) { "4.0.0-beta3" }

      it "preserves the pre-release formatting" do
        expect(requirement.requirements.first.last.to_s).to eq("4.0.0-beta3")
      end
    end

    context "with a build-version" do
      let(:requirement_string) { "4.0.0+something" }

      it "preserves the build version" do
        expect(requirement.requirements.first.last.to_s)
          .to eq("4.0.0+something")
      end
    end

    context "with no specifier" do
      let(:requirement_string) { "1.1.0" }

      it { is_expected.to eq(described_class.new("= 1.1.0")) }
    end

    context "with a caret version" do
      context "when specified to version" do
        let(:requirement_string) { "^1.2.3" }

        d = described_class.new(">=1.2.3", "<2.0.0")
        it { is_expected.to eq(d) }

        context "with a zero major" do
          let(:requirement_string) { "^0.2.3" }

          it { is_expected.to eq(described_class.new(">= 0.2.3", "< 0.3.0")) }

          context "when dealing with a zero minor" do
            let(:requirement_string) { "^0.0.3" }

            it { is_expected.to eq(described_class.new(">= 0.0.3", "< 0.0.4")) }
          end
        end
      end
    end

    context "with a > version specified" do
      let(:requirement_string) { ">1.5.1" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end

    context "with lower bound" do
      let(:requirement_string) { ">1.5.1" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.5.1")) }
    end

    context "with upper bound" do
      let(:requirement_string) { "<2.0.0" }

      it { is_expected.to eq(Gem::Requirement.new("< 2.0.0")) }
    end

    context "with lower and upper bound" do
      let(:requirement_string) { ">1.2.3 <2.0.0" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.2.3", "< 2.0.0")) }
    end
  end

  describe ".parse_dep_string" do
    context "with exact version" do
      it "parses package:version format" do
        result = described_class.parse_dep_string("intl:0.18.0")
        expect(result[:name]).to eq("intl")
        expect(result[:normalised_name]).to eq("intl")
        expect(result[:version]).to eq("0.18.0")
        expect(result[:requirement]).to eq("0.18.0")
        expect(result[:extras]).to be_nil
      end
    end

    context "with caret version" do
      it "parses package:^version format" do
        result = described_class.parse_dep_string("json_annotation:^4.8.0")
        expect(result[:name]).to eq("json_annotation")
        expect(result[:normalised_name]).to eq("json_annotation")
        expect(result[:version]).to eq("4.8.0")
        expect(result[:requirement]).to eq("^4.8.0")
      end
    end

    context "with tilde version" do
      it "parses package:~version format" do
        result = described_class.parse_dep_string("yaml:~3.1.0")
        expect(result[:name]).to eq("yaml")
        expect(result[:version]).to eq("3.1.0")
        expect(result[:requirement]).to eq("~3.1.0")
      end
    end

    context "with >= constraint" do
      it "parses package:>=version format" do
        result = described_class.parse_dep_string("collection:>=1.17.0")
        expect(result[:name]).to eq("collection")
        expect(result[:version]).to eq("1.17.0")
        expect(result[:requirement]).to eq(">=1.17.0")
      end
    end

    context "with > constraint" do
      it "parses package:>version format" do
        result = described_class.parse_dep_string("http:>1.0.0")
        expect(result[:name]).to eq("http")
        expect(result[:version]).to eq("1.0.0")
        expect(result[:requirement]).to eq(">1.0.0")
      end
    end

    context "with underscore in name" do
      it "normalises the name" do
        result = described_class.parse_dep_string("flutter_lints:2.0.0")
        expect(result[:name]).to eq("flutter_lints")
        expect(result[:normalised_name]).to eq("flutter_lints")
      end
    end

    context "with hyphen in name" do
      it "normalises the name by replacing hyphens with underscores" do
        result = described_class.parse_dep_string("my-package:1.0.0")
        expect(result[:name]).to eq("my-package")
        expect(result[:normalised_name]).to eq("my_package")
      end
    end

    context "with pre-release version" do
      it "parses pre-release versions" do
        result = described_class.parse_dep_string("package:1.0.0-beta.1")
        expect(result[:name]).to eq("package")
        expect(result[:version]).to eq("1.0.0-beta.1")
        expect(result[:requirement]).to eq("1.0.0-beta.1")
      end
    end

    context "with build metadata" do
      it "parses build metadata in versions" do
        result = described_class.parse_dep_string("package:1.0.0+build.123")
        expect(result[:name]).to eq("package")
        expect(result[:version]).to eq("1.0.0+build.123")
      end
    end

    context "with whitespace" do
      it "handles leading and trailing whitespace" do
        result = described_class.parse_dep_string("  intl:0.18.0  ")
        expect(result[:name]).to eq("intl")
        expect(result[:version]).to eq("0.18.0")
      end

      it "handles whitespace around constraint" do
        result = described_class.parse_dep_string("intl: 0.18.0")
        expect(result[:name]).to eq("intl")
        expect(result[:version]).to eq("0.18.0")
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

      it "returns nil when missing version" do
        result = described_class.parse_dep_string("intl:")
        expect(result).to be_nil
      end

      it "returns nil when missing colon separator" do
        result = described_class.parse_dep_string("intl@0.18.0")
        expect(result).to be_nil
      end

      it "returns nil when only package name" do
        result = described_class.parse_dep_string("intl")
        expect(result).to be_nil
      end
    end
  end
end
