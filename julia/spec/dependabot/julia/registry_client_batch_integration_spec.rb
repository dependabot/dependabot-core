# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/registry_client"
require "dependabot/dependency"

RSpec.describe Dependabot::Julia::RegistryClient, :julia_helpers do
  subject(:client) { described_class.new(credentials: credentials, custom_registries: []) }

  let(:credentials) { [] }

  describe "batch operations integration" do
    describe "batch_get_package_info" do
      it "successfully fetches info for multiple real packages" do
        dependencies = [
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

        result = client.batch_fetch_package_info(dependencies)

        expect(result).to be_a(Hash)
        expect(result["Example"]).to be_a(Hash)
        expect(result["Example"]["available_versions"]).to be_an(Array)
        expect(result["Example"]["latest_version"]).to be_a(String)

        expect(result["JSON"]).to be_a(Hash)
        expect(result["JSON"]["available_versions"]).to be_an(Array)
        expect(result["JSON"]["latest_version"]).to be_a(String)
      end
    end

    describe "batch_get_available_versions" do
      it "successfully fetches versions for multiple packages" do
        dependencies = [
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

        result = client.batch_fetch_available_versions(dependencies)

        expect(result).to be_a(Hash)
        expect(result["Example"]).to have_key("versions")
        expect(result["Example"]["versions"]).to be_an(Array)
        expect(result["Example"]["versions"]).not_to be_empty

        expect(result["JSON"]).to have_key("versions")
        expect(result["JSON"]["versions"]).to be_an(Array)
        expect(result["JSON"]["versions"]).not_to be_empty
      end
    end

    describe "batch_get_version_release_dates" do
      it "successfully fetches release dates for multiple packages" do
        packages_versions = [
          {
            name: "Example",
            uuid: "7876af07-990d-54b4-ab0e-23690620f79a",
            versions: ["0.5.3", "0.5.4"]
          },
          {
            name: "JSON",
            uuid: "682c06a0-de6a-54ab-a142-c8b1cf79cde6",
            versions: ["0.21.0", "0.21.1"]
          }
        ]

        result = client.batch_fetch_version_release_dates(packages_versions)

        expect(result).to be_a(Hash)
        expect(result["Example"]).to be_a(Hash)
        expect(result["Example"]["0.5.3"]).to eq("2019-07-17T05:33:46")
        expect(result["JSON"]).to be_a(Hash)
        expect(result["JSON"]["0.21.0"]).to eq("2019-07-16T19:58:10")
      end
    end

    describe "performance characteristics" do
      it "processes multiple packages without errors" do
        dependencies = [
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
          ),
          Dependabot::Dependency.new(
            name: "Pkg",
            version: "1.0.0",
            requirements: [],
            package_manager: "julia",
            metadata: { julia_uuid: "44cfe95a-1eb2-52ea-b672-e2afdf69b78f" }
          )
        ]

        result = nil
        expect do
          result = client.batch_fetch_package_info(dependencies)
        end.not_to raise_error

        expect(result.keys.length).to eq(3)
      end
    end
  end
end
