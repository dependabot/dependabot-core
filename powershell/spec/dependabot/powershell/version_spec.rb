# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/version"

RSpec.describe Dependabot::Powershell::Version do
  describe ".update_type" do
    it "classifies major, minor, patch, and revision-only updates" do
      expected_types = {
        ["1.2.3", "2.0.0"] => "major",
        ["1.2.3", "1.3.0"] => "minor",
        ["1.2.3", "1.2.4"] => "patch",
        ["1.2.3.4", "1.2.3.5"] => "patch",
        ["1.2", "1.2.0"] => "patch"
      }

      expected_types.each do |(previous, current), expected_type|
        expect(described_class.update_type(previous, current)).to eq(expected_type)
      end
    end

    it "does not classify removal of a native version component as an update" do
      expect(described_class.update_type("1.2.0", "1.2")).to be_nil
    end

    it "leaves same-core prerelease-only changes unclassified" do
      expect(described_class.update_type("1.2.3-beta1", "1.2.3-beta2")).to be_nil
    end
  end
end
