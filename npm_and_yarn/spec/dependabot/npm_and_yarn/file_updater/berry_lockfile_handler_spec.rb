# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/berry_lockfile_handler"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::BerryLockfileHandler do
  let(:fixture_path) do
    File.join("spec", "fixtures", "projects", "yarn_berry", "security_update", "yarn.lock")
  end

  describe ".parse" do
    it "parses a valid yarn berry lockfile" do
      parsed = described_class.parse(fixture_path)
      expect(parsed).to be_a(Hash)
      expect(parsed.keys).to include("__metadata")
    end

    it "returns nil for a non-existent file" do
      expect(described_class.parse("nonexistent.lock")).to be_nil
    end
  end

  describe ".split_descriptor" do
    it "splits a simple descriptor" do
      name, version = described_class.split_descriptor("axios@npm:^1.15.0")
      expect(name).to eq("axios")
      expect(version).to eq("npm:^1.15.0")
    end

    it "splits a scoped package descriptor" do
      name, version = described_class.split_descriptor("@scope/pkg@npm:^1.0.0")
      expect(name).to eq("@scope/pkg")
      expect(version).to eq("npm:^1.0.0")
    end

    it "handles descriptor without version" do
      name, version = described_class.split_descriptor("axios")
      expect(name).to eq("axios")
      expect(version).to be_nil
    end

    it "handles scoped package without version" do
      name, version = described_class.split_descriptor("@scope/pkg")
      expect(name).to eq("@scope/pkg")
      expect(version).to be_nil
    end
  end

  describe ".version_matches?" do
    let(:parsed) do
      {
        "axios@npm:^1.15.0" => { "version" => "1.15.0", "resolution" => "axios@npm:1.15.0" },
        "@scope/pkg@npm:^2.0.0" => { "version" => "2.1.0", "resolution" => "@scope/pkg@npm:2.1.0" },
        "__metadata" => { "version" => 8 }
      }
    end

    it "returns true when version matches" do
      expect(described_class.version_matches?(parsed, "axios", "1.15.0")).to be true
    end

    it "returns false when version differs" do
      expect(described_class.version_matches?(parsed, "axios", "1.15.2")).to be false
    end

    it "returns false for unknown dependency" do
      expect(described_class.version_matches?(parsed, "unknown-pkg", "1.0.0")).to be false
    end

    it "handles scoped packages" do
      expect(described_class.version_matches?(parsed, "@scope/pkg", "2.1.0")).to be true
      expect(described_class.version_matches?(parsed, "@scope/pkg", "2.0.0")).to be false
    end

    context "with composite keys" do
      let(:parsed) do
        {
          "lodash@npm:1.3.1, lodash@npm:^1.3.1" => { "version" => "1.3.1" }
        }
      end

      it "matches composite keys" do
        expect(described_class.version_matches?(parsed, "lodash", "1.3.1")).to be true
        expect(described_class.version_matches?(parsed, "lodash", "1.3.0")).to be false
      end
    end
  end

  describe ".find_exact_key" do
    let(:parsed) do
      {
        "axios@npm:1.15.2" => { "version" => "1.15.2" },
        "lodash@npm:^1.3.1" => { "version" => "1.3.1" },
        "@scope/pkg@npm:2.0.0" => { "version" => "2.0.0" }
      }
    end

    it "finds exact version key" do
      expect(described_class.find_exact_key(parsed, "axios", "1.15.2")).to eq("axios@npm:1.15.2")
    end

    it "finds scoped package key" do
      expect(described_class.find_exact_key(parsed, "@scope/pkg", "2.0.0")).to eq("@scope/pkg@npm:2.0.0")
    end

    it "returns nil when not found" do
      expect(described_class.find_exact_key(parsed, "axios", "9.9.9")).to be_nil
    end

    it "does not match range keys" do
      expect(described_class.find_exact_key(parsed, "lodash", "1.3")).to be_nil
    end
  end

  describe ".extract_protocol" do
    it "extracts npm protocol" do
      expect(described_class.extract_protocol("axios@npm:1.15.2", "axios")).to eq("npm:")
    end

    it "extracts protocol from scoped package" do
      expect(described_class.extract_protocol("@scope/pkg@npm:^1.0.0", "@scope/pkg")).to eq("npm:")
    end

    it "extracts protocol from composite key" do
      expect(described_class.extract_protocol("lodash@npm:1.3.1, lodash@npm:^1.3.1", "lodash")).to eq("npm:")
    end

    it "returns empty string when no protocol" do
      expect(described_class.extract_protocol("axios@1.15.2", "axios")).to eq("")
    end
  end

  describe ".replace_declaration" do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:lockfile_path) { File.join(tmp_dir, "yarn.lock") }

    after { FileUtils.rm_rf(tmp_dir) }

    it "replaces exact descriptor with range" do
      File.write(lockfile_path, <<~YAML)
        "axios@npm:1.15.2":
          version: 1.15.2
          resolution: "axios@npm:1.15.2"
          checksum: abc123
      YAML

      described_class.replace_declaration(lockfile_path, "axios", "1.15.2", "^1.15.2")

      content = File.read(lockfile_path)
      expect(content).to include('"axios@npm:^1.15.2":')
      expect(content).not_to include('"axios@npm:1.15.2":')
      expect(content).to include("version: 1.15.2")
      expect(content).to include('resolution: "axios@npm:1.15.2"')
    end

    it "handles tilde ranges" do
      File.write(lockfile_path, <<~YAML)
        "lodash@npm:1.3.1":
          version: 1.3.1
          resolution: "lodash@npm:1.3.1"
      YAML

      described_class.replace_declaration(lockfile_path, "lodash", "1.3.1", "~1.3.1")

      content = File.read(lockfile_path)
      expect(content).to include('"lodash@npm:~1.3.1":')
    end

    it "handles scoped packages" do
      File.write(lockfile_path, <<~YAML)
        "@scope/pkg@npm:2.0.0":
          version: 2.0.0
          resolution: "@scope/pkg@npm:2.0.0"
      YAML

      described_class.replace_declaration(lockfile_path, "@scope/pkg", "2.0.0", "^2.0.0")

      content = File.read(lockfile_path)
      expect(content).to include('"@scope/pkg@npm:^2.0.0":')
    end

    it "does nothing when exact key not found" do
      original = <<~YAML
        "axios@npm:^1.15.0":
          version: 1.15.0
      YAML
      File.write(lockfile_path, original)

      described_class.replace_declaration(lockfile_path, "axios", "1.15.2", "^1.15.2")

      expect(File.read(lockfile_path)).to eq(original)
    end
  end
end
