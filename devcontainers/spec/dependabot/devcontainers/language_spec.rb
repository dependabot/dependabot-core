# typed: false
# frozen_string_literal: true

require "dependabot/devcontainers/language"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Devcontainers::Language do
  subject(:language) { described_class.new(version) }

  let(:version) { "1.17.3" }

  describe "#version" do
    it "returns the version" do
      expect(language.version.to_s).to eq version
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(language.name).to eq(Dependabot::Devcontainers::LANGUAGE)
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
