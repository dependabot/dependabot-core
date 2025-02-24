# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/package/package_language"
require "dependabot/version"
require "dependabot/python/requirement"

RSpec.describe Dependabot::Python::Package::PackageLanguage do
  let(:name) { "python" }
  let(:version) { Dependabot::Version.new("3.8") }
  let(:requirement) { Dependabot::Python::Requirement.new(">=3.6") }

  describe "#initialize" do
    it "creates a PackageLanguage object with all attributes" do
      language = described_class.new(name: name, version: version, requirement: requirement)

      expect(language.name).to eq("python")
      expect(language.version).to eq(version)
      expect(language.requirement).to eq(requirement)
    end

    it "creates a PackageLanguage object with only name" do
      language = described_class.new(name: name)

      expect(language.name).to eq("python")
      expect(language.version).to be_nil
      expect(language.requirement).to be_nil
    end
  end
end
