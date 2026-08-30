# typed: false
# frozen_string_literal: true

require "open3"
require "spec_helper"
require "dependabot/powershell/package/package_details_fetcher"

RSpec.describe Dependabot::Powershell::Package::PackageDetailsFetcher do
  it "retains the registry constants on the facade" do
    expect(described_class::MAR_API_BASE).to eq("https://mcr.microsoft.com")
    expect(described_class::MAR_REPOSITORY_PREFIX).to eq("psresource/")
    expect(described_class::MAR_OPEN_TIMEOUT_IN_SECONDS).to eq(2)
    expect(described_class::MAR_READ_TIMEOUT_IN_SECONDS).to eq(60)
    expect(described_class::MAR_SOURCE).to eq(type: "registry", url: "https://mcr.microsoft.com")
    expect(described_class::PSGALLERY_API_BASE).to eq("https://www.powershellgallery.com/api/v2")
    expect(described_class::PSGALLERY_WEB_BASE).to eq("https://www.powershellgallery.com")
    expect(described_class::PSGALLERY_SOURCE).to eq(
      type: "registry",
      url: "https://www.powershellgallery.com/api/v2"
    )
    expect(described_class::UNLISTED_PUBLISHED_DATE).to eq("1900-01-01T00:00:00")
    expect(described_class::InvalidMarPagination).to be < described_class::InvalidMarResponse
  end

  %w(mar_fetcher mar_registry powershell_gallery_fetcher).each do |helper|
    it "supports loading #{helper} directly" do
      code = %(require "dependabot/powershell/package/package_details_fetcher/#{helper}")
      _stdout, stderr, status = Open3.capture3(Gem.ruby, "-Ilib", "-e", code)

      expect(status).to be_success, stderr
    end
  end
end
