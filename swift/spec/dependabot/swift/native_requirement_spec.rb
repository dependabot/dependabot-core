# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/native_requirement"

RSpec.describe Dependabot::Swift::NativeRequirement do
  RSpec::Matchers.define :parse_as do |requirement|
    match do |declaration|
      described_class.new(declaration).to_s == requirement
    end
  end

  describe ".new" do
    it "parses different ways of declaring requirements" do
      expect(requirement).to be(">= 1.0.0, < 2.0.0")
      expect(requirement).to be(">= 1.0.0, < 2.0.0")

      expect(requirement).to be("= 1.0.0")
      expect(requirement).to be("= 1.0.0")

      expect(requirement).to be(">= 1.0.0, < 2.0.0")
      expect(requirement).to be(">= 1.0.0, < 2.0.0")
      expect(requirement).to be(">= 1.0.0, < 2.0.0")
      expect(requirement).to be(">= 1.0.0, < 2.0.0")

      expect(requirement).to be(">= 1.0.0, < 1.1.0")
      expect(requirement).to be(">= 1.0.0, < 1.1.0")
      expect(requirement).to be(">= 1.0.0, < 1.1.0")
      expect(requirement).to be(">= 1.0.0, < 1.1.0")

      expect(requirement).to be("= 1.0.0")
      expect(requirement).to be("= 1.0.0")
      expect(requirement).to be("= 1.0.0")

      expect(requirement).to be(">= 1.0.0, < 2.0.0")
      expect(requirement).to be(">= 1.0.0, <= 2.0.0")
    end
  end
end
