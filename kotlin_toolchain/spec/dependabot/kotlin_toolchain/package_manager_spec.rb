# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/kotlin_toolchain/package_manager"

RSpec.describe Dependabot::KotlinToolchain::PackageManager do
  subject(:package_manager) { described_class.new(detected_version: "0.12.0-dev-4188") }

  it "reports the ecosystem package manager name and version" do
    expect(package_manager.name).to eq("kotlin-toolchain")
    expect(package_manager.version.to_s).to eq("0.12.0-dev-4188")
    expect(package_manager.detected_version.to_s).to eq("0.12.0-dev-4188")
  end

  it "accepts versions newer than the supported list" do
    expect(package_manager).not_to be_unsupported
  end

  context "with a development build of the minimum version" do
    subject(:package_manager) { described_class.new(detected_version: "0.11.0-dev-1") }

    it "is supported even though Maven orders it below the release" do
      expect(package_manager).not_to be_unsupported
      expect { package_manager.raise_if_unsupported! }.not_to raise_error
    end
  end

  context "with a version below the minimum" do
    subject(:package_manager) { described_class.new(detected_version: "0.10.0") }

    it "is unsupported and refuses to run" do
      expect(package_manager).to be_unsupported
      expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
    end
  end
end
