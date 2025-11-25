# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/conda_registry_client"
require "webmock/rspec"

RSpec.describe Dependabot::Conda::CondaRegistryClient do
  subject(:client) { described_class.new }

  let(:api_base_url) { "https://api.anaconda.org" }

  describe "#fetch_package_metadata" do
    context "when package exists" do
      let(:package_name) { "numpy" }
      let(:channel) { "anaconda" }
      let(:response_body) do
        {
          "name" => "numpy",
          "versions" => ["1.21.0", "1.22.0", "1.23.0"],
          "latest_version" => "1.23.0",
          "home" => "https://numpy.org",
          "dev_url" => "https://github.com/numpy/numpy",
          "summary" => "Array processing for numbers, strings, records, and objects.",
          "license" => "BSD-3-Clause"
        }.to_json
      end

      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
          .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
      end

      it "returns parsed package metadata" do
        metadata = client.fetch_package_metadata(package_name, channel)
        expect(metadata).not_to be_nil
        expect(metadata["name"]).to eq("numpy")
        expect(metadata["versions"]).to eq(["1.21.0", "1.22.0", "1.23.0"])
        expect(metadata["latest_version"]).to eq("1.23.0")
      end

      it "caches the result" do
        # First call
        client.fetch_package_metadata(package_name, channel)
        # Second call should use cache
        metadata = client.fetch_package_metadata(package_name, channel)

        expect(metadata["name"]).to eq("numpy")
        # Should only make one HTTP request (cached)
        expect(WebMock).to have_requested(:get, "#{api_base_url}/package/#{channel}/#{package_name}").once
      end
    end

    context "when package does not exist" do
      let(:package_name) { "nonexistent-package" }
      let(:channel) { "anaconda" }

      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
          .to_return(
            status: 404,
            body: { "error" => "\"#{package_name}\" could not be found" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns nil" do
        metadata = client.fetch_package_metadata(package_name, channel)
        expect(metadata).to be_nil
      end

      it "caches 404 responses" do
        # First call
        client.fetch_package_metadata(package_name, channel)
        # Second call should use cache (no HTTP request)
        metadata = client.fetch_package_metadata(package_name, channel)

        expect(metadata).to be_nil
        # Should only make one HTTP request (404 cached)
        expect(WebMock).to have_requested(:get, "#{api_base_url}/package/#{channel}/#{package_name}").once
      end
    end

    context "when API returns rate limit error" do
      let(:package_name) { "numpy" }
      let(:channel) { "anaconda" }

      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
          .to_return(status: 429, headers: { "Retry-After" => "60" })
      end

      it "raises DependabotError with retry information" do
        expect do
          client.fetch_package_metadata(package_name, channel)
        end.to raise_error(Dependabot::DependabotError, /rate limited.*60 seconds/)
      end
    end

    context "when API returns invalid JSON" do
      let(:package_name) { "numpy" }
      let(:channel) { "anaconda" }

      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
          .to_return(status: 200, body: "invalid json")
      end

      it "returns nil and logs error" do
        expect(Dependabot.logger).to receive(:error).with(/Invalid JSON/)
        metadata = client.fetch_package_metadata(package_name, channel)
        expect(metadata).to be_nil
      end
    end

    context "when connection times out" do
      let(:package_name) { "numpy" }
      let(:channel) { "anaconda" }

      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
          .to_timeout
      end

      it "raises DependabotError" do
        expect do
          client.fetch_package_metadata(package_name, channel)
        end.to raise_error(Dependabot::DependabotError, /Failed to connect/)
      end
    end
  end

  describe "#version_exists?" do
    let(:package_name) { "numpy" }
    let(:channel) { "anaconda" }
    let(:response_body) do
      {
        "name" => "numpy",
        "versions" => ["1.21.0", "1.22.0", "1.23.0"]
      }.to_json
    end

    before do
      stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    context "when version exists" do
      it "returns true" do
        expect(client.version_exists?(package_name, "1.22.0", channel)).to be true
      end
    end

    context "when version does not exist" do
      it "returns false" do
        expect(client.version_exists?(package_name, "2.0.0", channel)).to be false
      end
    end

    context "when package does not exist" do
      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/nonexistent")
          .to_return(status: 404)
      end

      it "returns false" do
        expect(client.version_exists?("nonexistent", "1.0.0", channel)).to be false
      end
    end
  end

  describe "#available_versions" do
    let(:package_name) { "numpy" }
    let(:channel) { "conda-forge" }
    let(:response_body) do
      {
        "name" => "numpy",
        "versions" => ["1.21.0", "1.23.0", "1.22.0", "1.20.0"] # Unsorted
      }.to_json
    end

    before do
      stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "returns sorted versions (newest first)" do
      versions = client.available_versions(package_name, channel)
      expect(versions.map(&:to_s)).to eq(["1.23.0", "1.22.0", "1.21.0", "1.20.0"])
    end

    it "returns Version objects" do
      versions = client.available_versions(package_name, channel)
      expect(versions).to all(be_a(Dependabot::Conda::Version))
    end

    context "with invalid version formats" do
      let(:response_body) do
        {
          "name" => "numpy",
          "versions" => ["1.21.0", "", "1.22.0"]
        }.to_json
      end

      it "skips invalid versions and continues" do
        expect(Dependabot.logger).to receive(:debug).with(/Skipping invalid/)
        versions = client.available_versions(package_name, channel)
        expect(versions.map(&:to_s)).to eq(["1.22.0", "1.21.0"])
      end
    end

    context "when package does not exist" do
      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/nonexistent")
          .to_return(status: 404)
      end

      it "returns empty array" do
        versions = client.available_versions("nonexistent", channel)
        expect(versions).to eq([])
      end
    end
  end

  describe "#latest_version" do
    let(:package_name) { "r-ggplot2" }
    let(:channel) { "conda-forge" }
    let(:response_body) do
      {
        "name" => "r-ggplot2",
        "versions" => ["3.3.0", "3.4.0", "3.3.5", "4.0.0"] # Unsorted
      }.to_json
    end

    before do
      stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "returns the latest version" do
      latest = client.latest_version(package_name, channel)
      expect(latest&.to_s).to eq("4.0.0")
    end

    it "returns a Version object" do
      latest = client.latest_version(package_name, channel)
      expect(latest).to be_a(Dependabot::Conda::Version)
    end

    context "when package does not exist" do
      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/nonexistent")
          .to_return(status: 404)
      end

      it "returns nil" do
        latest = client.latest_version("nonexistent", channel)
        expect(latest).to be_nil
      end
    end
  end

  describe "#package_metadata" do
    let(:package_name) { "numpy" }
    let(:channel) { "anaconda" }
    let(:response_body) do
      {
        "name" => "numpy",
        "home" => "https://numpy.org",
        "dev_url" => "https://github.com/numpy/numpy",
        "summary" => "Array processing for numbers, strings, records, and objects.",
        "license" => "BSD-3-Clause"
      }.to_json
    end

    before do
      stub_request(:get, "#{api_base_url}/package/#{channel}/#{package_name}")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "returns metadata hash with expected fields" do
      metadata = client.package_metadata(package_name, channel)
      expect(metadata).to eq(
        homepage: "https://numpy.org",
        source_url: "https://github.com/numpy/numpy",
        description: "Array processing for numbers, strings, records, and objects.",
        license: "BSD-3-Clause"
      )
    end

    context "when package does not exist" do
      before do
        stub_request(:get, "#{api_base_url}/package/#{channel}/nonexistent")
          .to_return(status: 404)
      end

      it "returns nil" do
        metadata = client.package_metadata("nonexistent", channel)
        expect(metadata).to be_nil
      end
    end
  end

  describe "default channel behavior" do
    let(:package_name) { "numpy" }
    let(:response_body) do
      {
        "name" => "numpy",
        "versions" => ["1.21.0"]
      }.to_json
    end

    before do
      stub_request(:get, "#{api_base_url}/package/anaconda/#{package_name}")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end

    it "uses 'anaconda' as default channel when not specified" do
      metadata = client.fetch_package_metadata(package_name)
      expect(metadata).not_to be_nil
      expect(WebMock).to have_requested(:get, "#{api_base_url}/package/anaconda/#{package_name}")
    end
  end
end
