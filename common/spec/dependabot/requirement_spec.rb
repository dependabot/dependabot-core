# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/requirement"
require "dependabot/version"

# Define an anonymous subclass of Dependabot::Requirement for testing purposes
TestRequirement = Class.new(Dependabot::Requirement) do
  sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
  def self.requirements_array(requirement_string)
    [new(requirement_string)]
  end

  # Initialize with comma-separated requirement constraints
  def initialize(constraint_string)
    requirements = constraint_string.split(",").map(&:strip)
    super(requirements)
  end
end

RSpec.describe Dependabot::Requirement do
  subject(:requirement) { TestRequirement.new(constraint_string) }

  describe "#constraints" do
    subject(:constraints) { requirement.constraints }

    let(:constraint_string) { ">= 1.0, < 2.0" }

    it "returns all constraint strings in the requirement" do
      expect(constraints).to eq([">= 1.0", "< 2.0"])
    end
  end

  describe "#min_version" do
    subject(:min_version) { requirement.min_version }

    context "when there is a single minimum constraint" do
      let(:constraint_string) { ">= 1.5" }

      it "returns the minimum version" do
        expect(min_version).to eq(Gem::Version.new("1.5"))
      end
    end

    context "when there are multiple minimum constraints" do
      let(:constraint_string) { ">= 1.0, > 1.5" }

      it "returns the maximum version among minimum constraints" do
        expect(min_version).to eq(Gem::Version.new("1.5"))
      end
    end

    context "when there are no minimum constraints" do
      let(:constraint_string) { "< 2.0" }

      it { is_expected.to be_nil }
    end
  end

  describe "#max_version" do
    subject(:max_version) { requirement.max_version }

    context "when there is a single maximum constraint" do
      let(:constraint_string) { "< 3.0" }

      it "returns the maximum version" do
        expect(max_version).to eq(Gem::Version.new("3.0"))
      end
    end

    context "when there are multiple maximum constraints" do
      let(:constraint_string) { "< 3.0, <= 2.5" }

      it "returns the minimum version among maximum constraints" do
        expect(max_version).to eq(Gem::Version.new("2.5"))
      end
    end

    context "when a constraint uses the '~>' operator with a minor version" do
      let(:constraint_string) { "~> 2.0" }

      it "returns the effective upper bound of the '~>' constraint" do
        expect(max_version).to eq(Gem::Version.new("2.1.0"))
      end
    end

    context "when a constraint uses the '~>' operator with a patch version" do
      let(:constraint_string) { "~> 2.5.1" }

      it "returns the effective upper bound of the '~>' constraint" do
        expect(max_version).to eq(Gem::Version.new("2.6.0"))
      end
    end

    context "when a constraint uses the '~>' operator with a major version only" do
      let(:constraint_string) { "~> 2" }

      it "returns the effective upper bound of the '~>' constraint" do
        expect(max_version).to eq(Gem::Version.new("3.0.0"))
      end
    end

    context "when there are no maximum constraints" do
      let(:constraint_string) { ">= 1.0" }

      it { is_expected.to be_nil }
    end
  end
end
