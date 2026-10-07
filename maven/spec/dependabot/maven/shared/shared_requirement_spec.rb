# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/shared/shared_requirement"
require "dependabot/maven/version"

RSpec.describe Dependabot::Maven::Shared::SharedRequirement do
  subject(:requirement) { test_requirement_class.new(requirement_string) }

  let(:requirement_string) { ">=1.0.0" }

  # Define a concrete subclass inside the describe block to avoid superclass mismatch
  # when multiple spec files are loaded in the same process.
  let(:test_requirement_class) do
    quoted = Gem::Requirement::OPS.keys.map { |k| Regexp.quote k }.join("|")
    version_pattern = Dependabot::Maven::Version::VERSION_PATTERN
    pattern_raw = "\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze
    pat = /\A#{pattern_raw}\z/
    rs_pattern = /\A\s*(#{quoted})\s*(#{version_pattern})\s*\z/

    Class.new(described_class) do
      const_set(:PATTERN_RAW, pattern_raw)
      const_set(:PATTERN, pat)
      const_set(:RUBY_STYLE_PATTERN, rs_pattern)

      define_singleton_method(:pattern) { pat }
      define_singleton_method(:ruby_style_pattern) { rs_pattern }

      define_singleton_method(:parse) do |obj|
        return ["=", Dependabot::Maven::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = pat.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise Gem::Requirement::BadRequirementError, msg
        end

        return Gem::Requirement::DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Dependabot::Maven::Version.new(matches[2])]
      end

      define_singleton_method(:requirements_array) do |requirement_string|
        split_java_requirement(requirement_string).map { |str| new(str) }
      end

      define_method(:satisfied_by?) do |version|
        version = Dependabot::Maven::Version.new(version.to_s)
        super(version)
      end
    end
  end

  describe "OR_SYNTAX" do
    it "is defined on the shared class" do
      expect(described_class::OR_SYNTAX).to eq(/(?<=\]|\)),/)
    end
  end

  describe ".split_java_requirement" do
    subject(:split) { test_requirement_class.send(:split_java_requirement, requirement_string) }

    context "with a simple version" do
      let(:requirement_string) { "1.0.0" }

      it { is_expected.to eq(["1.0.0"]) }
    end

    context "with nil" do
      let(:requirement_string) { nil }

      it { is_expected.to eq([""]) }
    end

    context "with two range requirements separated by OR_SYNTAX" do
      let(:requirement_string) { "(,1.0.0),(1.0.0,)" }

      it { is_expected.to contain_exactly("(,1.0.0)", "(1.0.0,)") }
    end

    context "with a single range requirement" do
      let(:requirement_string) { "[1.0.0,2.0.0)" }

      it { is_expected.to eq(["[1.0.0,2.0.0)"]) }
    end
  end

  describe "#initialize (convert_java_constraint_to_ruby_constraint)" do
    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0")) }
    end

    context "with an exclusive lower bound" do
      let(:requirement_string) { "(1.0.0,)" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.0.0")) }
    end

    context "with both bounds" do
      let(:requirement_string) { "(1.0.0, 2.0.0)" }

      it { is_expected.to eq(Gem::Requirement.new("> 1.0.0", "< 2.0.0")) }
    end

    context "with inclusive both bounds" do
      let(:requirement_string) { "[ 1.0.0,2.0.0 ]" }

      it { is_expected.to eq(Gem::Requirement.new(">= 1.0.0", "<= 2.0.0")) }
    end

    context "with a soft requirement" do
      let(:requirement_string) { "1.0.0" }

      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
    end

    context "with a hard requirement" do
      let(:requirement_string) { "[1.0.0]" }

      it { is_expected.to eq(Gem::Requirement.new("= 1.0.0")) }
    end

    context "with a dynamic version requirement (wildcard)" do
      let(:requirement_string) { "1.+" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new("~> 1.0").to_s) }
    end

    context "with just a + wildcard" do
      let(:requirement_string) { "+" }

      its(:to_s) { is_expected.to eq(Gem::Requirement.new(">= 0").to_s) }
    end

    context "with a comma-separated ruby style version requirement" do
      let(:requirement_string) { "~> 4.2.5, >= 4.2.5.1" }

      it { is_expected.to eq(test_requirement_class.new("~> 4.2.5", ">= 4.2.5.1")) }
    end

    context "when multiple Java reqs would be generated" do
      let(:requirement_string) { "(,1.0.0),(1.0.0,)" }

      it "raises an error" do
        expect { requirement }.to raise_error("Can't convert multiple Java reqs to a single Ruby one")
      end
    end
  end

  describe ".requirements_array" do
    subject(:array) { test_requirement_class.requirements_array(requirement_string) }

    context "with exact requirement" do
      let(:requirement_string) { "1.0.0" }

      it { is_expected.to eq([test_requirement_class.new("= 1.0.0")]) }
    end

    context "with a range requirement" do
      let(:requirement_string) { "[1.0.0,)" }

      it { is_expected.to eq([test_requirement_class.new(">= 1.0.0")]) }
    end

    context "with two range requirements" do
      let(:requirement_string) { "(,1.0.0),(1.0.0,)" }

      it "builds the correct array of requirements" do
        expect(array).to contain_exactly(test_requirement_class.new("> 1.0.0"), test_requirement_class.new("< 1.0.0"))
      end
    end
  end

  describe "#satisfied_by?" do
    subject { requirement.satisfied_by?(version) }

    context "with a satisfying version" do
      let(:version) { Dependabot::Maven::Version.new("1.0.0") }

      it { is_expected.to be(true) }
    end

    context "with an out-of-range version" do
      let(:version) { Dependabot::Maven::Version.new("0.9.0") }

      it { is_expected.to be(false) }
    end
  end
end
