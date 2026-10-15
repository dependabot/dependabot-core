# typed: false
# frozen_string_literal: true

require "spec_helper"
require "open3"
require "dependabot/composer/native_helpers"
require "dependabot/composer/package/registry_package"

RSpec.describe Dependabot::Composer::Package::RegistryPackage do
  subject(:package) { described_class.from_json(content, package_name: package_name, source: source) }

  let(:package_name) { "vendor/package" }
  let(:source) { "https://registry.example.test/packages.json" }
  let(:content) { JSON.generate(data) }
  let(:data) { { "packages" => { package_name.downcase => entries } } }
  let(:entries) do
    [
      { "version" => "v2.0.0", "time" => "2024-01-02T03:04:05+02:00",
        "dist" => { "url" => "https://example.test/2.zip" } },
      { "version" => "1.0.0", "time" => nil, "dist" => { "url" => nil } }
    ]
  end

  it "returns typed release fields without normalizing version strings" do
    expect(package.releases.first).to be_a(described_class::Release)
    expect(package.releases.first).to have_attributes(
      version_string: "v2.0.0",
      released_at: Time.iso8601("2024-01-02T03:04:05+02:00"),
      url: "https://example.test/2.zip"
    )
    expect(package.releases.last).to have_attributes(version_string: "1.0.0", released_at: nil, url: nil)
  end

  context "with a legacy map" do
    let(:data) do
      { "packages" => { package_name => { "arbitrary-key" => entries.first, "unrelated-key" => entries.last } } }
    end

    it "uses embedded versions and preserves the map's order" do
      expect(package.releases.map(&:version_string)).to eq(%w(v2.0.0 1.0.0))
    end
  end

  context "with uppercase letters in the requested name" do
    let(:package_name) { "Vendor/Package" }

    it "uses the downcased lookup key" do
      expect(package.releases.length).to eq(2)
    end
  end

  context "with unknown metadata and malformed unrelated packages" do
    let(:data) { super().tap { |fields| fields.fetch("packages")["other/package"] = false } }
    let(:entries) { super().map { |entry| entry.merge("require" => false, "source" => [], "unknown" => {}) } }

    it "reads only the target release projection" do
      expect(package.releases.map(&:version_string)).to eq(%w(v2.0.0 1.0.0))
    end
  end

  [
    nil, [], {}, { "unknown" => "data" }, { "packages" => nil }, { "packages" => [] }, { "packages" => {} },
    { "packages" => { "vendor/package" => nil } },
    { "packages" => { "vendor/package" => [] } },
    { "packages" => { "vendor/package" => {} } },
    { "packages" => { "other/package" => false }, "minified" => "unsupported" }
  ].each do |fields|
    context "with an empty response #{fields.inspect}" do
      let(:data) { fields }

      it "retains the empty release result" do
        expect(package.releases).to eq([])
      end
    end
  end

  context "with optional values omitted" do
    let(:entries) { [{ "version" => nil }, { "version" => "", "dist" => { "url" => "" } }, { "version" => "1.0.0" }] }

    it "preserves null versions, empty strings, and missing metadata" do
      expect(package.releases.map(&:version_string)).to eq([nil, "", "1.0.0"])
      expect(package.releases.map(&:released_at)).to eq([nil, nil, nil])
      expect(package.releases.map(&:url)).to eq([nil, "", nil])
    end
  end

  context "without a minification marker" do
    let(:entries) { [{ "version" => "__unset", "dist" => { "url" => "__unset" } }] }

    it "does not interpret ordinary string values as deletion markers" do
      expect(package.releases.first).to have_attributes(version_string: "__unset", url: "__unset")
    end
  end

  context "with a null minification marker" do
    let(:data) { super().merge("minified" => nil) }

    it "uses ordinary metadata without inheritance" do
      expect(package.releases.last).to have_attributes(version_string: "1.0.0", released_at: nil, url: nil)
    end
  end

  describe "minified metadata" do
    let(:data) { super().merge("minified" => "composer/2.0") }
    let(:entries) do
      [
        {
          "version" => "v3.0.0",
          "time" => "2024-01-02T03:04:05+02:00",
          "dist" => { "url" => "https://example.test/archive.zip", "type" => "zip" },
          "unused" => { "nested" => "__unset" }
        },
        { "version" => "v2.0.0" },
        { "version" => "v1.0.0", "time" => "__unset", "dist" => { "type" => "tar" } },
        { "version" => "v0.9.0", "dist" => "__unset" },
        { "version" => "v0.8.0", "time" => nil, "dist" => { "url" => "" } },
        {},
        { "version" => nil, "dist" => nil }
      ]
    end

    it "inherits fields, applies deletions, and replaces nested objects without changing earlier records" do
      releases = package.releases
      expect(releases.map(&:version_string)).to eq(["v3.0.0", "v2.0.0", "v1.0.0", "v0.9.0", "v0.8.0", "v0.8.0", nil])
      expect(releases.take(2).map(&:released_at)).to eq([Time.iso8601(entries.first.fetch("time"))] * 2)
      expect(releases.take(2).map(&:url)).to eq(["https://example.test/archive.zip"] * 2)
      expect(releases.drop(2).map(&:released_at)).to eq([nil] * 5)
      expect(releases.drop(2).map(&:url)).to eq([nil, nil, "", "", nil])
    end

    it "does not inherit state from a different response" do
      package.releases
      other = described_class.from_json(
        JSON.generate("minified" => "composer/2.0", "packages" => { package_name => [{ "version" => "1.0.0" }] }),
        package_name: package_name,
        source: source
      )
      expect(other.releases.first).to have_attributes(version_string: "1.0.0", released_at: nil, url: nil)
    end

    context "when the first record has a literal deletion marker" do
      let(:entries) { [{ "version" => "__unset", "dist" => { "url" => "__unset" } }] }

      it "does not apply a delta to the first record" do
        expect(package.releases.first).to have_attributes(version_string: "__unset", url: "__unset")
      end
    end

    shared_examples "PHP expansion parity" do
      it "matches the pinned native library's expansion through the public decoder" do
        php = <<~PHP
          require $argv[1];
          $rows = json_decode(stream_get_contents(STDIN), false, 512, JSON_THROW_ON_ERROR);
          $rows = array_map(static fn ($row) => (array) $row, $rows);
          $expanded = Composer\\MetadataMinifier\\MetadataMinifier::expand($rows);
          echo json_encode(array_map(static fn ($row) => (object) $row, $expanded), JSON_THROW_ON_ERROR);
        PHP
        autoload = File.join(Dependabot::Composer::NativeHelpers.composer_helpers_dir, "v2", "vendor", "autoload.php")
        stdout, stderr, status = Open3.capture3("php", "-r", php, autoload, stdin_data: JSON.generate(entries))
        expect(status.success?).to be(true), stderr

        expanded = described_class.from_json(
          JSON.generate("packages" => { package_name => JSON.parse(stdout) }),
          package_name: package_name,
          source: source
        )
        actual = package.releases.map { |release| [release.version_string, release.released_at, release.url] }
        expected = expanded.releases.map { |release| [release.version_string, release.released_at, release.url] }
        expect(actual).to eq(expected)
      end
    end

    it_behaves_like "PHP expansion parity"

    %w(
      illuminate--console.json
      illuminate--support.json
      illuminate-support-response.json
      symfony--polyfill-mbstring.json
      monolog--monolog.json
    ).each do |filename|
      context "with the real #{filename} response" do
        let(:data) { JSON.parse(fixture("packagist_responses", filename)) }
        let(:package_name) { data.fetch("packages").keys.first }
        let(:entries) { data.fetch("packages").fetch(package_name) }

        it_behaves_like "PHP expansion parity"
      end
    end
  end

  shared_examples "invalid registry metadata" do |field|
    let(:source) { "https://wire-user:wire-password@registry.example.test/packages.json?token=wire-query#wire-fragment" }

    it "raises a safe registry and field error without returning partial data" do
      expect { package }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
        expect(error.message).to include("https://registry.example.test/packages.json", package_name.downcase, field)
        expect(error.message).not_to include(
          "wire-user", "wire-password", "wire-query", "wire-fragment", "do-not-echo-this"
        )
        expect(error.cause).to be_nil
      end
    end
  end

  context "with invalid JSON" do
    let(:content) { '{"do-not-echo-this":' }

    it_behaves_like "invalid registry metadata", "valid JSON"
  end

  [false, true, 123, "do-not-echo-this", [{}]].each do |value|
    context "with a non-object response #{value.inspect}" do
      let(:data) { value }

      it_behaves_like "invalid registry metadata", "object"
    end
  end

  [false, 123, "do-not-echo-this", [{}]].each do |value|
    context "with malformed packages #{value.inspect}" do
      let(:data) { { "packages" => value } }

      it_behaves_like "invalid registry metadata", "packages"
    end
  end

  [false, 123, "do-not-echo-this"].each do |value|
    context "with a malformed target package #{value.inspect}" do
      let(:data) { { "packages" => { package_name => value } } }

      it_behaves_like "invalid registry metadata", "versions"
    end
  end

  [false, "composer/9.0", 123, {}].each do |value|
    context "with an unsupported minification marker #{value.inspect}" do
      let(:data) { super().merge("minified" => value) }

      it_behaves_like "invalid registry metadata", "minified"
    end
  end

  [nil, false, [], "do-not-echo-this"].each do |value|
    context "with a malformed trailing entry #{value.inspect}" do
      let(:entries) { [super().first, value] }

      it_behaves_like "invalid registry metadata", "releases[1]"
    end
  end

  [
    ["version", {}],
    ["version", { "version" => false }],
    ["version", { "version" => 123 }],
    ["time", { "version" => "1.0.0", "time" => false }],
    ["time", { "version" => "1.0.0", "time" => "do-not-echo-this" }],
    ["time", { "version" => "1.0.0", "time" => "" }],
    ["dist", { "version" => "1.0.0", "dist" => false }],
    ["dist", { "version" => "1.0.0", "dist" => [] }],
    ["dist.url", { "version" => "1.0.0", "dist" => { "url" => false } }]
  ].each do |field, entry|
    context "with invalid release #{entry}" do
      let(:entries) { [entry] }

      it_behaves_like "invalid registry metadata", "releases[0].#{field}"
    end
  end

  context "with malformed metadata on an unsupported version" do
    let(:entries) { [{ "version" => "not a version", "time" => false }] }

    it_behaves_like "invalid registry metadata", "releases[0].time"
  end

  context "with malformed metadata on a duplicate version" do
    let(:entries) { [super().first, super().first.merge("time" => false)] }

    it_behaves_like "invalid registry metadata", "releases[1].time"
  end
end
