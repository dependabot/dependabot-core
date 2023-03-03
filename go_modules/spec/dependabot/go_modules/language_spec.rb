# typed: false
# frozen_string_literal: true

require "dependabot/go_modules/language"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::GoModules::Language do
  let(:language) { described_class.new(version) }
  let(:version) { "3.0.0" }

  describe "#version" do
    it "returns the version" do
      expect(language.version).to eq(Dependabot::GoModules::Version.new(version))
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(language.name).to eq(Dependabot::GoModules::LANGUAGE)
    end
  end

  describe "#unsupported?" do
    it "returns false by default" do
      expect(language.unsupported?).to be false
    end
  end

  describe "#deprecated?" do
    it "returns false by default" do
      expect(language.deprecated?).to be false
    end
  end
end
