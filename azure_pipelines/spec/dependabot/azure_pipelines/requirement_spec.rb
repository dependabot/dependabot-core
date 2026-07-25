# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines/requirement"

RSpec.describe Dependabot::AzurePipelines::Requirement do
  describe ".requirements_array" do
    it "wraps a single requirement" do
      requirements = described_class.requirements_array(">= 4")

      expect(requirements.length).to eq(1)
      expect(requirements.first.to_s).to eq(">= 4")
    end
  end

  describe "#satisfied_by?" do
    it "treats a bare version as an exact pin" do
      expect(described_class.new("4")).to be_satisfied_by(Dependabot::AzurePipelines::Version.new("4"))
      expect(described_class.new("4")).not_to be_satisfied_by(Dependabot::AzurePipelines::Version.new("5"))
    end

    it "supports the operator forms an ignore condition can use" do
      requirement = described_class.new(">= 3, < 5")

      expect(requirement).to be_satisfied_by(Dependabot::AzurePipelines::Version.new("4"))
      expect(requirement).not_to be_satisfied_by(Dependabot::AzurePipelines::Version.new("5"))
    end
  end
end
