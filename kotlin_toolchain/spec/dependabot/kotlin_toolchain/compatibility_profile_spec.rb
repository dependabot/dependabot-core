# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/kotlin_toolchain/compatibility_profile"

RSpec.describe Dependabot::KotlinToolchain::CompatibilityProfile do
  it "uses the 0.11 schema without nested templates" do
    profile = described_class.for("0.11")

    expect(profile.name).to eq("0.11")
    expect(profile).not_to be_nested_templates
    expect(profile.built_ins.map { |entry| entry[:dependency] })
      .not_to include("org.jetbrains.kotlinx:dataframe-core")
  end

  it "adds DataFrame for 0.12" do
    profile = described_class.for("0.12.0-dev-4188")

    expect(profile.name).to eq("0.12")
    expect(profile).to be_nested_templates
    expect(profile.built_ins.map { |entry| entry[:dependency] })
      .to include("org.jetbrains.kotlinx:dataframe-core")
  end

  it "falls back for wrappers older than 0.11" do
    profile = described_class.for("0.10.3")

    expect(profile.name).to eq("legacy")
    expect(profile).to be_fallback
    expect(profile).not_to be_nested_templates
    expect(profile.built_ins).to be_empty
  end

  it "uses a safe future fallback" do
    profile = described_class.for("0.13.0")

    expect(profile.name).to eq("future")
    expect(profile).to be_fallback
  end
end
