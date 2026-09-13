# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/kotlin_toolchain"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::KotlinToolchain do
  it_behaves_like "it registers the required classes", "kotlin_toolchain"

  describe "the registered production check" do
    it "treats only test-scoped dependencies as development dependencies" do
      expect(dependency(groups: ["dependencies"]).production?).to be(true)
      expect(dependency(groups: ["toolchain"]).production?).to be(true)
      expect(dependency(groups: %w(dependencies test)).production?).to be(true)
      expect(dependency(groups: ["test"]).production?).to be(false)
      expect(dependency(groups: %w(test bom)).production?).to be(false)
    end
  end

  describe "the registered display name builder" do
    it "renames the wrapper dependency and leaves coordinates alone" do
      expect(dependency(name: "org.jetbrains.kotlin:kotlin-cli").display_name).to eq("kotlin-toolchain")
      expect(dependency(name: "io.ktor:ktor-server-core").display_name).to eq("io.ktor:ktor-server-core")
    end
  end

  def dependency(name: "io.ktor:ktor-server-core", groups: ["dependencies"])
    Dependabot::Dependency.new(
      name: name,
      version: "3.1.0",
      requirements: [{ requirement: "3.1.0", file: "module.yaml", groups: groups, source: nil }],
      package_manager: "kotlin_toolchain"
    )
  end
end
