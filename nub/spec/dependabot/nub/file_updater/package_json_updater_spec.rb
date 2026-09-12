# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub"

RSpec.describe Dependabot::Nub::FileUpdater::PackageJsonUpdater do
  let(:updater) do
    described_class.new(package_json: package_json, dependencies: [dependency])
  end
  let(:updated_package_json) { updater.updated_package_json }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "undici",
      version: "6.24.1",
      previous_version: "6.23.0",
      package_manager: "nub",
      requirements: [{
        file: "package.json",
        requirement: "^6.24.1",
        groups: ["dependencies"],
        source: nil
      }],
      previous_requirements: [{
        file: "package.json",
        requirement: "^6.23.0",
        groups: ["dependencies"],
        source: nil
      }]
    )
  end

  # A resolution value is a requirement string, so matching it against the whole
  # requirement hash silently skipped every range-based entry and fell back to the
  # exact version.
  context "with a range-based resolution for the dependency" do
    let(:package_json) do
      Dependabot::DependencyFile.new(
        name: "package.json",
        content: {
          name: "test",
          version: "1.0.0",
          dependencies: { undici: "^6.23.0" },
          resolutions: { undici: "^6.23.0" }
        }.to_json
      )
    end

    it "rewrites the resolution to the new requirement" do
      parsed = JSON.parse(updated_package_json.content)
      expect(parsed.dig("resolutions", "undici")).to eq("^6.24.1")
    end
  end

  context "with a range-based pnpm override for the dependency" do
    let(:package_json) do
      Dependabot::DependencyFile.new(
        name: "package.json",
        content: {
          name: "test",
          version: "1.0.0",
          dependencies: { undici: "^6.23.0" },
          pnpm: { overrides: { undici: "^6.23.0" } }
        }.to_json
      )
    end

    it "rewrites the override to the new requirement" do
      parsed = JSON.parse(updated_package_json.content)
      expect(parsed.dig("pnpm", "overrides", "undici")).to eq("^6.24.1")
    end
  end
end
