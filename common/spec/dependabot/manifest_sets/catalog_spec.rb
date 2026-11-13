# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/manifest_sets"

RSpec.describe Dependabot::ManifestSets::Catalog do
  def fixture(name)
    JSON.parse(File.read(File.join(Dependabot::ManifestSets::FIXTURES_DIR, name), encoding: "UTF-8"))
  end

  def parse_error(text)
    described_class.parse(text)
    nil
  rescue Dependabot::ManifestSets::InvalidCatalog => e
    e
  end

  let(:catalog) { Dependabot::ManifestSets.catalog }

  describe "the bundled catalog" do
    it "is valid and covers the initial ecosystems" do
      expect(catalog.ecosystems.map(&:id)).to eq(%w(pypi golang))
    end

    it "selects owners in order with a final fallback" do
      pypi = catalog.ecosystem("pypi")
      expect(pypi.owners.map(&:id)).to eq(%w(uv pip))
      expect(pypi.selector_basenames).to eq(["uv.lock"])
      expect(catalog.ecosystem("golang").owners.map(&:id)).to eq(["go_modules"])
    end

    it "only marks ecosystems whose inputs are all rule-matched" do
      expect(catalog.ecosystem("pypi").inputs_matched_by_rules).to be(false)
      expect(catalog.ecosystem("golang").inputs_matched_by_rules).to be(true)
    end
  end

  describe "shared fixtures" do
    fixture_cases = lambda do |name|
      JSON.parse(File.read(File.join(Dependabot::ManifestSets::FIXTURES_DIR, name), encoding: "UTF-8"))["cases"]
    end

    fixture_cases.call("filenames.json").each do |c|
      it "matches #{c['basename'].inspect} in #{c['ecosystem']} with #{c['matching_rules'].inspect}" do
        expect(catalog.ecosystem(c["ecosystem"]).matching_rule_ids(c["basename"])).to eq(c["matching_rules"])
      end
    end

    fixture_cases.call("owners.json").each do |c|
      it "selects #{c['owner']} for #{c['ecosystem']} #{c['basenames'].inspect}" do
        expect(catalog.ecosystem(c["ecosystem"]).select_owner(c["basenames"])&.id).to eq(c["owner"])
      end
    end

    fixture_cases.call("invalid_catalogs.json").each do |c|
      it "rejects a catalog with #{c['name']} as #{c['error']}" do
        expect(parse_error(c["catalog"])&.code).to eq(c["error"])
      end
    end

    it "pins every rule with at least one positive and one negative filename" do
      cases = fixture("filenames.json")["cases"]
      catalog.ecosystems.each do |ecosystem|
        own = cases.select { |c| c["ecosystem"] == ecosystem.id }
        ecosystem.path_rules.each do |rule|
          expect(own.any? { |c| c["matching_rules"].include?(rule.id) }).to be(true), rule.id
          expect(own.any? { |c| !c["matching_rules"].include?(rule.id) }).to be(true), rule.id
        end
      end
    end
  end

  describe "limits" do
    it "rejects more than #{described_class::MAX_RULES} rules" do
      rules = Array.new(described_class::MAX_RULES + 1) do |i|
        { "id" => "r#{i}", "filename_regex" => "\\Aa\\z", "directory" => "parent" }
      end
      doc = { "schema_version" => 1,
              "ecosystems" => [{ "id" => "e", "path_rules" => rules,
                                 "owners" => [{ "id" => "o", "otherwise" => true }] }] }
      expect(parse_error(JSON.generate(doc))&.code).to eq("too_many_rules")
    end

    it "rejects catalogs over #{described_class::MAX_BYTES} bytes before decoding" do
      text = "{\"schema_version\":1,\"ecosystems\":[]}#{' ' * described_class::MAX_BYTES}"
      expect(parse_error(text)&.code).to eq("catalog_too_large")
    end

    it "rejects invalid UTF-8" do
      expect(parse_error((+"{\"a\":\"\xFF\"}").force_encoding(Encoding::UTF_8))&.code).to eq("invalid_json")
    end

    it "allows 32 levels of nesting but not 33" do
      expect(parse_error(("[" * 32) + ("]" * 32))&.code).to eq("invalid_type")
      expect(parse_error(("[" * 33) + ("]" * 33))&.code).to eq("invalid_json")
    end
  end

  describe "catalog.schema.json" do
    let(:schema) { JSON.parse(File.read(Dependabot::ManifestSets::SCHEMA_PATH)) }
    let(:builder) { described_class::Builder }

    def required_fields(table)
      table.select { |_, required| required }.keys.sort
    end

    it "declares the same fields as the validator" do
      defs = schema.fetch("$defs")
      expect(schema["properties"].keys.sort).to eq(builder::ROOT_FIELDS.keys.sort)
      expect(schema["required"].sort).to eq(required_fields(builder::ROOT_FIELDS))
      {
        "ecosystem" => builder::ECOSYSTEM_FIELDS,
        "path_rule" => builder::RULE_FIELDS
      }.each do |name, table|
        expect(defs[name]["properties"].keys.sort).to eq(table.keys.sort), name
        expect(defs[name]["required"].sort).to eq(required_fields(table)), name
      end
      owner_fields = defs["owner"]["oneOf"].flat_map { |o| o["properties"].keys }.uniq.sort
      expect(owner_fields).to eq(builder::OWNER_FIELDS.keys.sort)
    end

    it "uses the validator's version, identifier pattern and limits" do
      expect(schema.dig("properties", "schema_version", "const")).to eq(described_class::SCHEMA_VERSION)
      expect(schema.dig("$defs", "identifier", "pattern"))
        .to eq(described_class::IDENTIFIER.source.sub("\\A", "^").sub("\\z", "$"))
      expect(schema.dig("$defs", "path_rule", "properties", "filename_regex", "maxLength"))
        .to eq(Dependabot::ManifestSets::PortableRegex::MAX_BYTES)
      expect(schema.dig("$defs", "path_rule", "properties", "directory", "const"))
        .to eq(described_class::DIRECTORY_PARENT)
    end
  end
end
