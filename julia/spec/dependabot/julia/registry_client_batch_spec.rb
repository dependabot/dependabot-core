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

        expect(result).to be_a(Dependabot::Julia::RegistryClient::Result::PackageInfoBatch)
        expect(result.packages).to be_empty
      end

      it "parses successful and failed package fields" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "Example" => {
              "available_versions" => ["0.5.4", "0.5.5"],
              "latest_version" => "0.5.5",
              "metadata" => {
                "name" => "Example",
                "uuid" => "7876af07-990d-54b4-ab0e-23690620f79a",
                "latest_version" => "0.5.5",
                "available_versions" => ["0.5.4", "0.5.5"]
              }
            },
            "Missing" => {
              "available_versions" => { "error" => "No versions found" },
              "latest_version" => { "error" => "Package not found" }
            }
          }
        )

        result = client.batch_fetch_package_info(dependencies)

        expect(result).to be_a(Dependabot::Julia::RegistryClient::Result::PackageInfoBatch)
        example = result.packages.fetch("Example")
        missing = result.packages.fetch("Missing")
        expect(example).to be_a(Dependabot::Julia::RegistryClient::Result::PackageInfo)
        expect(example.latest_version).to have_attributes(version: "0.5.5")
        expect(missing.available_versions).to be_a(Dependabot::Julia::RegistryClient::Result::Failure)
        expect(missing.available_versions.message).to eq("No versions found")
      end

      it "allows a package named error" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "error" => {
              "available_versions" => ["1.0.0"],
              "latest_version" => "1.0.0"
            }
          }
        )

        result = client.batch_fetch_package_info([dependencies.first])
        package_info = result.packages.fetch("error")

        expect(package_info).to be_a(Dependabot::Julia::RegistryClient::Result::PackageInfo)
        expect(package_info.latest_version).to have_attributes(version: "1.0.0")
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

        expect(result).to be_a(Dependabot::Julia::RegistryClient::Result::AvailableVersionsBatch)
        expect(result.packages).to be_empty
      end

      it "preserves per-package failures" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "Example" => { "versions" => ["0.5.4", "0.5.5"] },
            "Missing" => { "error" => "No versions found" }
          }
        )

        result = client.batch_fetch_available_versions(dependencies)

        expect(result.packages.fetch("Example")).to have_attributes(versions: ["0.5.4", "0.5.5"])
        expect(result.packages.fetch("Missing")).to be_a(
          Dependabot::Julia::RegistryClient::Result::Failure
        )
        expect(result.packages.fetch("Missing").message).to eq("No versions found")
      end

      it "allows a package named error" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "error" => { "versions" => ["1.0.0"] }
          }
        )

        result = client.batch_fetch_available_versions([dependencies.first])

        expect(result.packages.fetch("error")).to have_attributes(versions: ["1.0.0"])
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

        expect(result).to be_a(Dependabot::Julia::RegistryClient::Result::ReleaseDatesBatch)
        expect(result.packages).to be_empty
      end

      it "parses dates, missing dates, and per-version failures" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "Example" => {
              "0.5.0" => "2023-01-01T00:00:00Z",
              "0.5.1" => nil,
              "0.5.2" => { "error" => "Date unavailable" }
            }
          }
        )

        requests = packages_versions.map do |package|
          Dependabot::Julia::RegistryClient::Result::PackageVersionsRequest.new(**package)
        end
        result = client.batch_fetch_version_release_dates(requests)
        dates = result.packages.fetch("Example")

        expect(dates).to be_a(Dependabot::Julia::RegistryClient::Result::ReleaseDates)
        expect(dates.dates.fetch("0.5.0")).to have_attributes(release_date: "2023-01-01T00:00:00Z")
        expect(dates.dates.fetch("0.5.1")).to have_attributes(release_date: nil)
        expect(dates.dates.fetch("0.5.2")).to be_a(Dependabot::Julia::RegistryClient::Result::Failure)
        expect(dates.dates.fetch("0.5.2").message).to eq("Date unavailable")
      end

      it "allows a package named error" do
        allow(client).to receive(:call_julia_helper).and_return(
          {
            "error" => { "1.0.0" => "2023-01-01T00:00:00Z" }
          }
        )

        request = Dependabot::Julia::RegistryClient::Result::PackageVersionsRequest.new(
          name: "error",
          uuid: "11111111-1111-1111-1111-111111111111",
          versions: ["1.0.0"]
        )
        result = client.batch_fetch_version_release_dates([request])
        dates = result.packages.fetch("error")

        expect(dates).to be_a(Dependabot::Julia::RegistryClient::Result::ReleaseDates)
        expect(dates.dates.fetch("1.0.0")).to have_attributes(release_date: "2023-01-01T00:00:00Z")
      end
    end
  end
end
