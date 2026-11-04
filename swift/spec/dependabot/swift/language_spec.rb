# typed: strict
# frozen_string_literal: true

require "dependabot/swift/language"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Swift::Language do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Swift::Language) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:language) { described_class.new(version) }
  sig { returns(String) }
  let(:version) { "3.0.0" }
  # rubocop:enable RSpec/ScatteredLet

  describe "#version" do
    it "returns the version" do
      expect(language.version).to eq(Dependabot::Swift::Version.new(version))
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(language.name).to eq(Dependabot::Swift::LANGUAGE)
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
