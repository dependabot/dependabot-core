# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nimble/requirements_updater"

RSpec.describe Dependabot::Nimble::RequirementsUpdater do
  def updated(string, latest)
    requirement = Dependabot::DependencyRequirement.create(
      requirement: string, file: "example.nimble", groups: ["dependencies"], source: nil
    )
    described_class
      .new(requirements: [requirement], latest_version: Dependabot::Nimble::Version.new(latest))
      .updated_requirements.first.requirement
  end

  {
    ">= 1.2" => ">= 1.5.0",
    ">=1.2" => ">=1.5.0",
    "> 1.2" => ">= 1.5.0",
    "== 1.2" => "== 1.5.0",
    "1.2" => "1.5.0",
    "^= 1.2" => "^= 1.5.0",
    "~= 1.2.3" => "~= 1.5.0",
    ">= 1.2 & < 2.0" => ">= 1.5.0 & < 2.0",
    "< 2.0 & >= 1.2" => "< 2.0 & >= 1.5.0",
    ">= 1.5.0" => ">= 1.5.0"
  }.each do |current, expected|
    it "turns #{current.inspect} into #{expected.inspect} for 1.5.0" do
      expect(updated(current, "1.5.0")).to eq(expected)
    end
  end

  it "leaves a range alone when its upper bound excludes the latest version" do
    expect(updated(">= 1.2 & < 2.0", "2.1.0")).to eq(">= 1.2 & < 2.0")
    expect(updated("<= 1.9", "2.1.0")).to eq("<= 1.9")
  end

  it "leaves alone a package without a version" do
    expect(updated(nil, "1.5.0")).to be_nil
    expect(updated("*", "1.5.0")).to eq("*")
  end

  it "leaves alone what it does not understand" do
    expect(updated("#head", "1.5.0")).to eq("#head")
  end
end
