# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/kotlin_toolchain/version"

RSpec.describe Dependabot::KotlinToolchain::Version do
  it "orders dev builds numerically" do
    expect(described_class.new("0.12.0-dev-4188"))
      .to be > described_class.new("0.12.0-dev-4187")
  end

  it "orders the final release after its dev builds" do
    expect(described_class.new("0.12.0"))
      .to be > described_class.new("0.12.0-dev-4188")
  end

  it "registers for the ecosystem" do
    expect(Dependabot::Utils.version_class_for_package_manager("kotlin_toolchain"))
      .to eq(described_class)
  end
end
