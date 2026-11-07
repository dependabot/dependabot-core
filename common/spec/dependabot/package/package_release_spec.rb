# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/package_release"
require "dependabot/package/package_language"
require "dependabot/version"

RSpec.describe Dependabot::Package::PackageRelease do
  let(:version) { Dependabot::Version.new("2.0.0") }
  let(:released_at) { Time.parse("2023-01-01T12:00:00Z") }
  let(:language) do
    Dependabot::Package::PackageLanguage.new(
      name: "ruby",
      version: Dependabot::Version.new("2.7.6"),
      requirement: TestRequirement.new(">=2.5")
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
        url: "https://example.com/package-2.0.0.gem",
        package_type: "gem",
        language: language
      )

      expect(release.version).to eq(version)
      expect(release.released_at).to eq(released_at)
      expect(release.yanked).to be true
      expect(release.yanked_reason).to eq("Security issue")
      expect(release.downloads).to eq(5000)
      expect(release.url).to eq("https://example.com/package-2.0.0.gem")
      expect(release.package_type).to eq("gem")
      expect(release.language).to eq(language)
      expect(release.language.name).to eq("ruby")
      expect(release.language.version).to eq(Dependabot::Version.new("2.7.6"))
      expect(release.language.requirement).to eq(TestRequirement.new(">=2.5"))
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

  describe "#released_at=" do
    let(:details) { { "version_string" => "v2.0.0" } }
    let(:release) do
      described_class.new(
        version: version,
        released_at: released_at,
        latest: true,
        yanked: true,
        yanked_reason: "Security issue",
        downloads: 5000,
        url: "https://example.com/package-2.0.0.gem",
        package_type: "gem",
        language: language,
        tag: "v2.0.0",
        details: details
      )
    end

    it "updates the timestamp without changing other metadata" do
      new_time = Time.utc(2024, 1, 2)
      expect(release.public_send(:released_at=, new_time)).to eq(new_time)
      expect(release).to have_attributes(
        version: version,
        released_at: new_time,
        latest: true,
        yanked: true,
        yanked_reason: "Security issue",
        downloads: 5000,
        url: "https://example.com/package-2.0.0.gem",
        package_type: "gem",
        language: language,
        tag: "v2.0.0",
        details: details
      )
    end

    it "clears the timestamp on the same release object" do
      cached_release = release
      release.released_at = nil

      expect(cached_release).to equal(release)
      expect(cached_release.released_at).to be_nil
    end

    [false, "2024-01-02", 123, {}].each do |value|
      it "rejects assigning #{value.inspect}" do
        expect { release.released_at = value }.to raise_error(TypeError)
        expect(release.released_at).to eq(released_at)
      end
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
