# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/package/registry_package"

RSpec.describe Dependabot::Pub::Package::RegistryPackage do
  subject(:package) { described_class.from_json(JSON.dump(data)) }

  let(:data) do
    {
      "versions" => [
        { "version" => "1.0.0", "published" => "2024-01-01T00:00:00Z" },
        { "version" => "2.0.0", "published" => "2024-02-01T00:00:00Z" }
      ],
      "latest" => { "pubspec" => { "repository" => "https://example.test/repository" } }
    }
  end

  it "returns typed versions and complete dated releases" do
    expect(package.versions).to eq(
      [Dependabot::Pub::Version.new("1.0.0"), Dependabot::Pub::Version.new("2.0.0")]
    )
    expect(package.releases.map(&:released_at)).to eq(
      [Time.utc(2024, 1, 1), Time.utc(2024, 2, 1)]
    )
  end

  context "without publication metadata" do
    let(:data) { super().merge("versions" => [{ "version" => "1.0.0" }]) }

    it "allows security version enumeration without dates" do
      expect(package.versions.map(&:to_s)).to eq(["1.0.0"])
      expect { package.releases }.to raise_error(Dependabot::Pub::JsonValueParser::InvalidValue)
    end
  end

  context "with missing historical versions" do
    let(:data) { super().except("versions") }

    it "keeps optional metadata separate from mandatory security version enumeration" do
      expect(package.releases).to eq([])
      expect { package.versions }.to raise_error(
        Dependabot::Pub::JsonValueParser::InvalidValue, "Pub package versions must be an array"
      )
    end
  end

  context "with malformed historical data" do
    let(:data) { super().merge("versions" => false) }

    it "still reads repository metadata" do
      expect(package.source_url).to eq("https://example.test/repository")
    end
  end

  context "with a malformed later release" do
    let(:data) { super().merge("versions" => [{ "version" => "1.0.0", "published" => "2024-01-01" }, nil]) }

    it "does not return the partial list" do
      expect { package.releases }.to raise_error(
        Dependabot::Pub::JsonValueParser::InvalidValue, "Pub package versions[1] must be an object"
      )
    end
  end

  context "with no repository field" do
    let(:data) { { "latest" => { "pubspec" => { "homepage" => "https://example.test/homepage" } } } }

    it "uses the homepage" do
      expect(package.source_url).to eq("https://example.test/homepage")
    end
  end

  context "with both repository and homepage" do
    let(:data) do
      { "latest" => { "pubspec" => { "repository" => "https://example.test/repository", "homepage" => false } } }
    end

    it "does not read an unused malformed fallback" do
      expect(package.source_url).to eq("https://example.test/repository")
    end
  end

  context "without source metadata" do
    let(:data) { {} }

    it "returns no source URL" do
      expect(package.source_url).to be_nil
    end
  end
end
