# typed: false
# frozen_string_literal: true

require "dependabot/gradle/language"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Gradle::Language do
  let(:language) { described_class.new }

  describe "#version" do
    it "returns version as nil" do
      expect(language.version).to be_nil
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(language.name).to eq(Dependabot::Gradle::LANGUAGE)
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
