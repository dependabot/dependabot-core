# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/package/package_release"
require "dependabot/python/package/package_language"
require "dependabot/version"
require "dependabot/python/requirement"

RSpec.describe Dependabot::Python::Package::PackageRelease do
  let(:version) { Dependabot::Version.new("2.0.0") }
  let(:released_at) { Time.parse("2023-01-01T12:00:00Z") }
  let(:language) do
    Dependabot::Python::Package::PackageLanguage.new(
      name: "python",
      version: Dependabot::Version.new("3.8"),
      requirement: Dependabot::Python::Requirement.new(">=3.6")
    )
  end

  describe "#initialize" do
    it "creates a PackageRelease object with all attributes" do
      release = described_class.new(
        version: version,
        released_at: released_at,
        yanked: true,
        yanked_reason: "Security issue",
        downloads: 5000,
        url: "https://example.com/package-2.0.0.tar.gz",
        package_type: "sdist",
        language: language
      )

      expect(release.version).to eq(version)
      expect(release.released_at).to eq(released_at)
      expect(release.yanked).to be true
      expect(release.yanked_reason).to eq("Security issue")
      expect(release.downloads).to eq(5000)
      expect(release.url).to eq("https://example.com/package-2.0.0.tar.gz")
      expect(release.package_type).to eq("sdist")
      expect(release.language).to eq(language)
      expect(release.language.name).to eq("python")
      expect(release.language.version).to eq(Dependabot::Version.new("3.8"))
      expect(release.language.requirement).to eq(Dependabot::Python::Requirement.new(">=3.6"))
    end

    it "creates a PackageRelease object with only required attributes" do
      release = described_class.new(version: version)

      expect(release.version).to eq(version)
      expect(release.released_at).to be_nil
      expect(release.yanked).to be false
      expect(release.yanked_reason).to be_nil
      expect(release.downloads).to be_nil
      expect(release.url).to be_nil
      expect(release.package_type).to be_nil
      expect(release.language).to be_nil
    end
  end

  describe "#yanked?" do
    it "returns true if package is yanked" do
      release = described_class.new(version: version, yanked: true)
      expect(release.yanked?).to be true
    end

    it "returns false if package is not yanked" do
      release = described_class.new(version: version, yanked: false)
      expect(release.yanked?).to be false
    end
  end
end
