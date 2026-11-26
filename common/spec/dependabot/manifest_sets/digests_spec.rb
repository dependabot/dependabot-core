# typed: true
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "dependabot/manifest_sets"
require "dependabot/manifest_sets/digests"

RSpec.describe Dependabot::ManifestSets::Digests do
  let(:data_dir) { Dependabot::ManifestSets::DATA_DIR }

  it "is up to date with the published files (run bin/update-manifest-set-digests.rb)" do
    expect(File.read(described_class.manifest_path(data_dir))).to eq(described_class.render(data_dir))
  end

  it "publishes the catalog, its schema and every fixture" do
    expect(described_class.published_files(data_dir)).to include(
      "catalog.json",
      "catalog.schema.json",
      "fixtures/filenames.json",
      "fixtures/owners.json",
      "fixtures/invalid_catalogs.json"
    )
  end

  it "lists files sorted by bytes, never itself, with their sha256" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "fixtures"))
      File.write(File.join(dir, "b.json"), "b")
      File.write(File.join(dir, "Z.json"), "z")
      File.write(File.join(dir, "fixtures", "a.json"), "")
      File.write(File.join(dir, "notes.md"), "ignored")
      described_class.write(dir)

      manifest = JSON.parse(File.read(described_class.manifest_path(dir)))
      expect(manifest["schema_version"]).to eq(1)
      expect(manifest["algorithm"]).to eq("sha256")
      expect(manifest["files"]).to eq(
        [
          { "path" => "Z.json", "sha256" => Digest::SHA256.hexdigest("z") },
          { "path" => "b.json", "sha256" => Digest::SHA256.hexdigest("b") },
          { "path" => "fixtures/a.json", "sha256" => Digest::SHA256.hexdigest("") }
        ]
      )
      expect(described_class.up_to_date?(dir)).to be(true)

      File.write(File.join(dir, "b.json"), "changed")
      expect(described_class.up_to_date?(dir)).to be(false)
    end
  end
end
