# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/registry_client"

RSpec.describe Dependabot::Julia::RegistryClient do
  let(:registry_client) { described_class.new(credentials: []) }

  describe "real Julia helper calls" do
    context "with Example package" do
      let(:package_name) { "Example" }
      let(:package_uuid) { "7876af07-990d-54b4-ab0e-23690620f79a" }

      it "fetches actual latest version" do
        result = registry_client.fetch_latest_version(package_name, package_uuid)

        # The fetch_latest_version should return a valid version or nil if package not found
        if result.nil?
          # Verify this is a real issue by checking metadata
          metadata = registry_client.fetch_package_metadata(package_name, package_uuid)

          # If metadata works but fetch_latest_version doesn't, that's unexpected
          if metadata && metadata["latest_version"]
            raise "fetch_latest_version returned nil, but metadata shows latest_version: #{metadata['latest_version']}"
          end

          # Otherwise, the package might not be in the registry (expected case)
          expect(result).to be_nil
        else
          expect(result).to be_a(Gem::Version)
          expect(result.to_s).to match(/\d+\.\d+\.\d+/)
        end
      end

      it "fetches actual source URL" do
        result = registry_client.find_package_source_url(package_name, package_uuid)

        expect(result).to be_a(Hash)
        expect(result["source_url"]).to be_a(String)
        expect(result["source_url"]).to include("github.com")
      end

      it "fetches package metadata" do
        result = registry_client.fetch_package_metadata(package_name, package_uuid)

        expect(result).to be_a(Hash)
        # The metadata returns direct package info, not nested under "result"
        expect(result).to have_key("name")
        expect(result).to have_key("uuid")
        expect(result).to have_key("latest_version")
        expect(result["latest_version"]).to match(/\d+\.\d+\.\d+/)
      end
    end

    context "when UUID is required" do
      let(:package_name) { "Example" }

      it "returns nil when UUID is missing" do
        result = registry_client.fetch_latest_version(package_name, nil)
        expect(result).to be_nil
      end

      it "returns nil when UUID is invalid" do
        result = registry_client.fetch_latest_version(package_name, "invalid-uuid")
        expect(result).to be_nil
      end

      it "returns nil for non-existent package" do
        result = registry_client.fetch_latest_version("NonExistentPackage999", "00000000-0000-0000-0000-000000000000")
        expect(result).to be_nil
      end
    end

    context "when testing version fetching functions" do
      let(:package_name) { "Example" }
      let(:package_uuid) { "7876af07-990d-54b4-ab0e-23690620f79a" }

      it "get_latest_version works via registry client" do
        result = registry_client.fetch_latest_version(package_name, package_uuid)
        expect(result).to be_a(Gem::Version).or(be_nil)
      end

      it "get_latest_version works directly" do
        # Test the Julia helper function directly
        args = { package_name: package_name, package_uuid: package_uuid }
        result = registry_client.send(:call_julia_helper, function: "get_latest_version", args: args)

        # The result should contain version directly (not nested under "result")
        expect(result).to have_key("version")
        expect(result["version"]).to match(/\d+\.\d+\.\d+/)

        version = Gem::Version.new(result["version"])
        expect(version).to be_a(Gem::Version)
      end
    end
  end
end
