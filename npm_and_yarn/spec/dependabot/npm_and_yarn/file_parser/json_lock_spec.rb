# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser/json_lock"

RSpec.describe Dependabot::NpmAndYarn::FileParser::JsonLock do
  subject(:reader) { described_class.new(file, dealias_packages: dealias_packages) }

  let(:dealias_packages) { false }
  let(:file) { Dependabot::DependencyFile.new(name: "package-lock.json", content: content) }
  let(:content) { data.to_json }
  let(:entry) { { "version" => "1.0.0" } }
  let(:data) { { "lockfileVersion" => 3, "packages" => { "node_modules/example" => entry } } }

  describe "#dependencies" do
    subject(:dependencies) { reader.dependencies.dependencies }

    it "reads package records" do
      expect(dependencies.first).to have_attributes(name: "example", version: "1.0.0")
    end

    context "with an empty legacy map" do
      let(:data) { super().merge("dependencies" => {}) }

      it "does not merge the packages table" do
        expect(dependencies).to be_empty
      end
    end

    [nil, false].each do |legacy|
      context "with dependencies set to #{legacy.inspect}" do
        let(:data) { super().merge("dependencies" => legacy) }

        it "falls back to packages" do
          expect(dependencies.map(&:name)).to eq(["example"])
        end
      end
    end

    context "with an ignored root and a versionless link" do
      let(:data) do
        {
          "lockfileVersion" => 3,
          "packages" => {
            "" => false,
            "node_modules/local" => { "link" => true, "dependencies" => "unconsumed" },
            "node_modules/example" => entry
          }
        }
      end

      it "does not read fields below skipped entries" do
        expect(dependencies.map(&:name)).to eq(["example"])
      end
    end

    context "with an invalid version string" do
      let(:entry) { { "version" => "not-semver", "dependencies" => "unconsumed", "dev" => "unconsumed" } }

      it "skips the entry before reading metadata or children" do
        expect(dependencies).to be_empty
      end
    end

    context "with a nested legacy dependency" do
      let(:data) do
        {
          "lockfileVersion" => 1,
          "dependencies" => {
            "example" => { "version" => "1.0.0", "dependencies" => { "child" => { "version" => "2.0.0" } } }
          }
        }
      end

      it "preserves recursion" do
        expect(dependencies.map(&:name)).to eq(%w(example child))
      end
    end

    context "with modern dependency requirement strings" do
      let(:data) do
        {
          "lockfileVersion" => 3,
          "packages" => {
            "node_modules/example" => { "version" => "1.0.0", "dependencies" => { "child" => "^2.0.0" } },
            "node_modules/child" => { "version" => "2.0.0" }
          }
        }
      end

      it "reads versions from package records rather than dependency specifiers" do
        expect(dependencies.map(&:name)).to eq(%w(example child))
      end
    end

    context "with both bundled and dev metadata" do
      let(:entry) { super().merge("bundled" => true, "dev" => true) }

      it "preserves the dev metadata override" do
        expect(dependencies.first.subdependency_metadata).to eq([{ production: false }])
      end
    end

    context "with bundled metadata only" do
      let(:entry) { super().merge("bundled" => true, "dev" => false) }

      it "retains the bundled flag" do
        expect(dependencies.first.subdependency_metadata).to eq([{ npm_bundled: true }])
      end
    end

    context "with an unconsumed malformed alias hint" do
      let(:entry) { super().merge("name" => 1) }

      it "uses the package key without dealiasing" do
        expect(dependencies.first.name).to eq("example")
      end

      context "with dealiasing enabled" do
        let(:dealias_packages) { true }

        it "reports the consumed name field" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable, /name must be a string or nil/)
        end
      end
    end

    context "with an alias followed by a regular package" do
      let(:dealias_packages) { true }
      let(:data) do
        {
          "lockfileVersion" => 3,
          "packages" => {
            "node_modules/alias" => { "name" => "real", "version" => "1.0.0" },
            "node_modules/ordinary" => { "version" => "2.0.0" }
          }
        }
      end

      it "does not carry alias metadata into later entries" do
        expect(dependencies.first.metadata).to eq(alias: "alias")
        expect(dependencies.last.metadata).to be_empty
      end
    end

    [["version", 1], %w(dev true), ["bundled", []], ["dependencies", []]].each do |field, value|
      context "with malformed #{field}" do
        let(:entry) { super().merge(field => value) }

        it "reports the consumed field and file" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable, /#{field}/) do |error|
            expect(error.file_name).to eq("package-lock.json")
          end
        end
      end
    end
  end

  describe "#legacy_dependencies" do
    let(:data) { { "dependencies" => { "example" => entry }, "packages" => { "ignored" => {} } } }

    it "exposes typed legacy entries without including packages" do
      expect(reader.legacy_dependencies.keys).to eq(["example"])
      expect(reader.legacy_dependencies.fetch("example").version).to eq("1.0.0")
    end

    it "uses the registry default only for an absent resolved key" do
      uri = reader.legacy_dependencies.fetch("example").registry_uri("https://registry.example")
      expect(uri.to_s).to eq("https://registry.example")
    end

    [nil, false, 1, "not a URI"].each do |value|
      context "with resolved set to #{value.inspect}" do
        let(:entry) { super().merge("resolved" => value) }

        it "preserves URI filtering without applying the missing-key default" do
          expect(reader.legacy_dependencies.fetch("example").registry_uri("https://registry.example")).to be_nil
        end
      end
    end
  end

  describe "#details" do
    it "does not inspect unused metadata" do
      entry["dev"] = "unconsumed"
      entry["resolution"] = {}
      expect(reader.details("example", nil, "package.json")).to have_attributes(version: "1.0.0", resolution: nil)
    end

    it "leaves the input file unchanged" do
      original = file.content.dup
      reader.dependencies
      reader.details("example", nil, "package.json")
      expect(file.content).to eq(original)
    end
  end
end
