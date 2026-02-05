# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_parsers"
require "dependabot/pre_commit/additional_dependency_parsers/python"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyParsers do
  describe ".for_language" do
    it "returns the Python parser for 'python'" do
      expect(described_class.for_language("python")).to eq(
        Dependabot::PreCommit::AdditionalDependencyParsers::Python
      )
    end

    it "is case-insensitive" do
      expect(described_class.for_language("Python")).to eq(
        Dependabot::PreCommit::AdditionalDependencyParsers::Python
      )
    end

    it "raises for unsupported languages" do
      expect { described_class.for_language("unknown") }.to raise_error(
        /Unsupported language for additional_dependencies parsing: unknown/
      )
    end
  end

  describe ".supported?" do
    it "returns true for python" do
      expect(described_class.supported?("python")).to be true
    end

    it "returns false for unsupported languages" do
      expect(described_class.supported?("unknown")).to be false
    end
  end

  describe ".supported_languages" do
    it "includes python" do
      expect(described_class.supported_languages).to include("python")
    end
  end
end
