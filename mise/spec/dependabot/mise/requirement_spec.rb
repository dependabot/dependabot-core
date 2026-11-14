# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/requirement"
require "dependabot/mise/version"

RSpec.describe Dependabot::Mise::Requirement do
  describe "#satisfied_by?" do
    {
      "*rc*" => { "28.0-rc1" => true, "1.19.0-rc.1-otp-27" => true, "27.3.2" => false },
      "27.*" => { "27.3.2" => true, "27.0-rc1" => true, "28.0.0" => false },
      ">= 27, < 28" => { "27.3.2" => true, "26.2.5" => false, "28.0.0" => false },
      "27.*, < 27.3.3" => { "27.3.2" => true, "27.3.3" => false, "28.0.0" => false },
      "27.*, *rc*" => { "27.0-rc1" => true, "27.3.2" => false, "28.0-rc1" => false }
    }.each do |requirement, expectations|
      expectations.each do |version, satisfied|
        it "returns #{satisfied} for #{version} with #{requirement.inspect}" do
          expect(described_class.new(requirement).satisfied_by?(Dependabot::Mise::Version.new(version)))
            .to be(satisfied)
        end
      end
    end
  end

  describe ".requirements_array" do
    it "keeps comma-separated constraints in one requirement" do
      requirements = described_class.requirements_array("27.*, < 27.3.3")

      expect(requirements.length).to eq(1)
      expect(requirements.first.satisfied_by?(Dependabot::Mise::Version.new("27.3.3"))).to be(false)
    end
  end
end
