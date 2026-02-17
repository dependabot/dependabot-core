# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/requirement"

RSpec.describe Dependabot::Conda::Requirement, ".parse_dep_string" do
  subject(:result) { described_class.parse_dep_string(dep_string) }

  context "with a simple name=version string (conda style)" do
    let(:dep_string) { "numpy=1.26.0" }

    it "parses the name and version" do
      expect(result).to eq(
        name: "numpy",
        normalised_name: "numpy",
        version: "1.26.0",
        requirement: "==1.26.0",
        extras: nil
      )
    end
  end

  context "with == operator (pip style)" do
    let(:dep_string) { "pandas==2.0.0" }

    it "parses the name and version" do
      expect(result).to eq(
        name: "pandas",
        normalised_name: "pandas",
        version: "2.0.0",
        requirement: "==2.0.0",
        extras: nil
      )
    end
  end

  context "with >= operator" do
    let(:dep_string) { "scipy>=1.10.0" }

    it "parses the name with lower bound" do
      expect(result).to eq(
        name: "scipy",
        normalised_name: "scipy",
        version: "1.10.0",
        requirement: ">=1.10.0",
        extras: nil
      )
    end
  end

  context "with ~= operator (compatible release)" do
    let(:dep_string) { "matplotlib~=3.7.0" }

    it "parses the name with compatible release" do
      expect(result).to eq(
        name: "matplotlib",
        normalised_name: "matplotlib",
        version: "3.7.0",
        requirement: "~=3.7.0",
        extras: nil
      )
    end
  end

  context "with channel prefix" do
    let(:dep_string) { "conda-forge::pytorch=2.0.0" }

    it "parses the channel as extras" do
      expect(result).to eq(
        name: "pytorch",
        normalised_name: "pytorch",
        version: "2.0.0",
        requirement: "==2.0.0",
        extras: "conda-forge"
      )
    end
  end

  context "with underscore in package name" do
    let(:dep_string) { "scikit_learn=1.3.0" }

    it "normalises underscores to hyphens" do
      expect(result).to eq(
        name: "scikit_learn",
        normalised_name: "scikit-learn",
        version: "1.3.0",
        requirement: "==1.3.0",
        extras: nil
      )
    end
  end

  context "with complex version string" do
    let(:dep_string) { "tensorflow=2.15.0.post1" }

    it "parses complex version strings" do
      expect(result).to eq(
        name: "tensorflow",
        normalised_name: "tensorflow",
        version: "2.15.0.post1",
        requirement: "==2.15.0.post1",
        extras: nil
      )
    end
  end

  context "with no version specified" do
    let(:dep_string) { "requests" }

    it "returns nil" do
      expect(result).to be_nil
    end
  end

  context "with empty string" do
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

  context "with whitespace around the string" do
    let(:dep_string) { "  numpy=1.26.0  " }

    it "trims whitespace and parses correctly" do
      expect(result).to eq(
        name: "numpy",
        normalised_name: "numpy",
        version: "1.26.0",
        requirement: "==1.26.0",
        extras: nil
      )
    end
  end

  context "with > operator" do
    let(:dep_string) { "flask>2.0.0" }

    it "parses the name with greater than constraint" do
      expect(result).to eq(
        name: "flask",
        normalised_name: "flask",
        version: "2.0.0",
        requirement: ">2.0.0",
        extras: nil
      )
    end
  end

  context "with < operator" do
    let(:dep_string) { "django<4.0.0" }

    it "parses the name with less than constraint" do
      expect(result).to eq(
        name: "django",
        normalised_name: "django",
        version: "4.0.0",
        requirement: "<4.0.0",
        extras: nil
      )
    end
  end

  context "with <= operator" do
    let(:dep_string) { "requests<=2.31.0" }

    it "parses the name with less than or equal constraint" do
      expect(result).to eq(
        name: "requests",
        normalised_name: "requests",
        version: "2.31.0",
        requirement: "<=2.31.0",
        extras: nil
      )
    end
  end

  context "with != operator" do
    let(:dep_string) { "pytest!=7.0.0" }

    it "parses the name with not equal constraint" do
      expect(result).to eq(
        name: "pytest",
        normalised_name: "pytest",
        version: "7.0.0",
        requirement: "!=7.0.0",
        extras: nil
      )
    end
  end
end
