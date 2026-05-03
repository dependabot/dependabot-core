# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/home_assistant_manifest_updater"

RSpec.describe Dependabot::Python::FileUpdater::HomeAssistantManifestUpdater do
  let(:manifest_content) do
    fixture("home_assistant", "manifest.json").gsub("aiohue==1.9.1", "aiohue==1.8.0")
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "custom_components/kia_uvo/manifest.json",
      content: manifest_content
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "aiohue",
      version: "1.9.1",
      previous_version: "1.8.0",
      requirements: [{
        requirement: "==1.9.1",
        file: "custom_components/kia_uvo/manifest.json",
        source: nil,
        groups: []
      }],
      previous_requirements: [{
        requirement: "==1.8.0",
        file: "custom_components/kia_uvo/manifest.json",
        source: nil,
        groups: []
      }],
      package_manager: "pip"
    )
  end
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: [manifest],
      credentials: []
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the matching Home Assistant requirement and preserves the rest" do
      expect(updated_files.map(&:name)).to eq(["custom_components/kia_uvo/manifest.json"])

      updated_manifest = JSON.parse(updated_files.first.content)
      expect(updated_manifest["domain"]).to eq("kia_uvo")
      expect(updated_manifest["requirements"]).to eq(["aiohue==1.9.1", "voluptuous==0.13.1"])
    end
  end
end
