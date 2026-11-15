# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nimble/requirement"
require "dependabot/nimble/version"

RSpec.describe Dependabot::Nimble::Requirement do
  def requirement(string) = described_class.new(string)

  def version(string) = Dependabot::Nimble::Version.new(string)

  describe "#satisfied_by?" do
    it "treats a bare version as an exact requirement" do
      expect(requirement("1.2.3")).to be_satisfied_by(version("1.2.3"))
      expect(requirement("1.2.3")).not_to be_satisfied_by(version("1.2.4"))
    end

    it "understands the comparison operators" do
      expect(requirement(">= 1.2")).to be_satisfied_by(version("1.2"))
      expect(requirement("> 1.2")).not_to be_satisfied_by(version("1.2"))
      expect(requirement("< 1.2")).to be_satisfied_by(version("1.1.9"))
      expect(requirement("<= 1.2")).to be_satisfied_by(version("1.2"))
      expect(requirement("== 1.2")).to be_satisfied_by(version("1.2"))
    end

    it "keeps a caret range below the next incompatible version" do
      expect(requirement("^= 1.2.3")).to be_satisfied_by(version("1.9.0"))
      expect(requirement("^= 1.2.3")).not_to be_satisfied_by(version("2.0.0"))
      expect(requirement("^= 0.2.3")).to be_satisfied_by(version("0.2.9"))
      expect(requirement("^= 0.2.3")).not_to be_satisfied_by(version("0.3.0"))
      expect(requirement("^= 0.0.3")).not_to be_satisfied_by(version("0.0.4"))
    end

    it "keeps a tilde range below the next minor version" do
      expect(requirement("~= 1.2.3")).to be_satisfied_by(version("1.2.9"))
      expect(requirement("~= 1.2.3")).not_to be_satisfied_by(version("1.3.0"))
      expect(requirement("~= 1.2")).to be_satisfied_by(version("1.9"))
      expect(requirement("~= 1.2")).not_to be_satisfied_by(version("2.0"))
    end

    it "requires both sides of an intersection" do
      expect(requirement(">= 1.0 & < 2.0")).to be_satisfied_by(version("1.5"))
      expect(requirement(">= 1.0 & < 2.0")).not_to be_satisfied_by(version("2.0"))
    end

    it "accepts any version for `*` and for nothing" do
      expect(requirement("*")).to be_satisfied_by(version("9.9.9"))
      expect(requirement("")).to be_satisfied_by(version("0.0.1"))
      expect(requirement(nil)).to be_satisfied_by(version("0.0.1"))
    end

    it "rejects what is not a range" do
      expect { requirement("#head") }.to raise_error(Gem::Requirement::BadRequirementError)
      expect { requirement(">= 1.0 & < 2.0 junk junk") }.to raise_error(Gem::Requirement::BadRequirementError)
    end
  end

  describe ".next_incompatible" do
    {
      ["1.2.3", true] => "2.0.0", ["0.2.3", true] => "0.3.0", ["0.0.3", true] => "0.0.4",
      ["1", true] => "2.0.0", ["1.2", true] => "2.0.0",
      ["1.2.3", false] => "1.3.0", ["1.2", false] => "2.0.0", ["1", false] => "2.0.0"
    }.each do |(string, semver), expected|
      it "excludes #{expected} from #{semver ? '^=' : '~='} #{string}" do
        expect(described_class.next_incompatible(string, semver: semver)).to eq(expected)
      end
    end
  end

  describe ".lower_bound" do
    it "reads the version a range starts from" do
      expect(described_class.lower_bound(">= 1.2")).to eq("1.2")
      expect(described_class.lower_bound("^= 1.2.3")).to eq("1.2.3")
      expect(described_class.lower_bound("1.2.3")).to eq("1.2.3")
      expect(described_class.lower_bound("< 2.0 & >= 1.0")).to eq("1.0")
    end

    it "has none for an upper bound only, or for no version" do
      expect(described_class.lower_bound("< 2.0")).to be_nil
      expect(described_class.lower_bound("")).to be_nil
      expect(described_class.lower_bound(nil)).to be_nil
    end
  end
end
