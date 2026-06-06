# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/prek/requirement"

RSpec.describe Dependabot::Prek::Requirement do
  it "is registered as the requirement class for the prek package manager" do
    expect(Dependabot::Utils.requirement_class_for_package_manager("prek")).to eq(described_class)
  end

  describe ".requirements_array" do
    it "wraps a single requirement string in an array" do
      expect(described_class.requirements_array(">= 1.0.0")).to eq([described_class.new(">= 1.0.0")])
    end
  end
end
