# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/registry_client"
require "dependabot/dependency"

RSpec.describe Dependabot::Julia::RegistryClient do
  let(:credentials) { [] }
  let(:custom_registries) { [] }
  let(:client) do
    described_class.new(
      credentials: credentials,
      custom_registries: custom_registries
    )
  end

  describe "batch operations" do
    describe "#batch_fetch_package_info" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Example",
            version: "0.5.3",
            requirements: [],
            package_manager: "julia",
            metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
          ),
          Dependabot::Dependency.new(
            name: "JSON",
            version: "0.21.0",
            requirements: [],
            package_manager: "julia",
            metadata: { julia_uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6" }
          )
        ]
      end

      it "returns empty hash when dependencies list is empty" do
        result = client.batch_fetch_package_info([])

        expect(result).to be_a(Hash)
        expect(result).to be_empty
      end
    end

    describe "#batch_fetch_available_versions" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Example",
            version: "0.5.3",
            requirements: [],
            package_manager: "julia",
            metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
          ),
          Dependabot::Dependency.new(
            name: "JSON",
            version: "0.21.0",
            requirements: [],
            package_manager: "julia",
            metadata: { julia_uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6" }
          )
        ]
      end

      it "returns empty hash when dependencies list is empty" do
        result = client.batch_fetch_available_versions([])

        expect(result).to be_a(Hash)
        expect(result).to be_empty
      end
    end

    describe "#batch_fetch_version_release_dates" do
      let(:packages_versions) do
        [
          {
            name: "Example",
            uuid: "7876af07-990d-54b4-ab0e-23690620f79a",
            versions: ["0.5.0", "0.5.1", "0.5.2"]
          },
          {
            name: "JSON",
            uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6",
            versions: ["0.21.0", "0.21.1"]
          }
        ]
      end

      it "returns empty hash structure when packages_versions is empty" do
        result = client.batch_fetch_version_release_dates([])

        expect(result).to be_a(Hash)
        expect(result).to be_empty
      end
    end
  end
end
