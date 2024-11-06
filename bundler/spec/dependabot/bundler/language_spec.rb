# typed: false
# frozen_string_literal: true

require "dependabot/bundler/language"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Bundler::Language do
  let(:language) { described_class.new(version) }
  let(:version) { "3.0.0" }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "3.0.0" }

      it "sets the version correctly" do
        expect(language.version).to eq(Dependabot::Bundler::Version.new(version))
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Bundler::LANGUAGE)
      end
    end

    context "when version is a Dependabot::Bundler::Version" do
      let(:version) { "3.0.0" }

      it "sets the version correctly" do
        expect(language.version).to eq(version)
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Bundler::LANGUAGE)
      end
    end
  end

  describe "#unsupported?" do
    it "returns false by default as no specific support or deprecation for languages is currently defined" do
      expect(language.unsupported?).to be false
    end
  end

  describe "#deprecated?" do
    it "returns false by default as no specific deprecation for languages is currently defined" do
      expect(language.deprecated?).to be false
    end
  end
end
