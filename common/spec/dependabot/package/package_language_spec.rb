# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/package_language"
require "dependabot/version"

RSpec.describe Dependabot::Package::PackageLanguage do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:name) { "ruby" }

  sig { returns(Dependabot::Version) }
  let(:version) { Dependabot::Version.new("2.7.6") }

  sig { returns(Dependabot::Requirement) }
  let(:requirement) { TestRequirement.new(">=2.5") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#initialize" do
    it "creates a PackageLanguage object with all attributes" do
      language = described_class.new(name: name, version: version, requirement: requirement)

      expect(language.name).to eq("ruby")
      expect(language.version).to eq(version)
      expect(language.requirement).to eq(requirement)
    end

    it "creates a PackageLanguage object with only name" do
      language = described_class.new(name: name)

      expect(language.name).to eq("ruby")
      expect(language.version).to be_nil
      expect(language.requirement).to be_nil
    end
  end
end
