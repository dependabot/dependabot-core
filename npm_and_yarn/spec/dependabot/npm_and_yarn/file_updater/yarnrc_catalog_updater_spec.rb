# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/yarn_catalogs"
require "dependabot/npm_and_yarn/file_updater/yarnrc_catalog_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::YarnrcCatalogUpdater do
  let(:files) { project_dependency_files("yarn_berry/catalog_workspace") }
  let(:catalogs) { Dependabot::NpmAndYarn::YarnCatalogs.new(dependency_files: files) }
  let(:requirement) do
    {
      requirement: "^2.8.6", file: ".yarnrc.yml", groups: %w(devDependencies dependencies), source: nil,
      metadata: { yarn_catalog_reference: "catalog:", yarn_catalog_package: "prettier" }
    }
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "prettier",
      version: "2.8.6",
      package_manager: "npm_and_yarn",
      requirements: [requirement],
      previous_requirements: [requirement.merge(requirement: "2.8.0")]
    )
  end
  let(:updater) { described_class.new(catalogs: catalogs, dependencies: [dependency]) }

  let(:catalog_lines) { ["\uFEFF# 🎨 Catalog ranges", "catalog:", '  prettier: "2.8.0" # keep', ""] }

  it "edits only the selected scalar and preserves source bytes including quotes and comments" do
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
  end

  it "edits an unquoted partial range in a numeric named catalog without changing unrelated scalars" do
    catalogs.config_file.content = "flag: false\nvalue: null\ncatalogs:\n  2025:\n    prettier: 2.8 # keep comment\n"
    files.select { |file| file.name.end_with?("package.json") }.each do |file|
      file.content = file.content.gsub("catalog:", "catalog:2025")
    end
    requirement[:metadata][:yarn_catalog_reference] = "catalog:2025"
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub("2.8 #", "^2.8.6 #"))
    expect(updater.updated_content(pins: { "prettier" => "2.9" }))
      .to eq(catalogs.config_file.content.sub("2.8 #", '"2.9" #'))
  end

  context "with Unicode and CRLF before the selected scalar" do
    before do
      file = files.find { |candidate| candidate.name == ".yarnrc.yml" }
      file.content = file.content.sub("# Shared formatting version", "# 🎨 Shared formatting version").gsub("\n", "\r\n")
    end

    it "preserves source offsets and line endings" do
      expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
    end
  end

  it "preserves character offsets in flow mappings with Unicode on the same line" do
    catalogs.config_file.content = "{label: '🎨', catalog: {prettier: \"2.8.0\"}}\r\n"
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
  end

  {
    "LF" => "\n", "CRLF" => "\r\n", "CR" => "\r", "NEL" => "\u0085", "LS" => "\u2028", "PS" => "\u2029"
  }.each do |label, newline|
    it "preserves #{label} line endings, BOM, Unicode, and comments around catalog edits" do
      content = catalog_lines.join(newline)
      catalogs.config_file.content = content
      expect(updater.updated_content).to eq(content.sub('"2.8.0"', '"^2.8.6"'))
      expect(updater.updated_content(pins: { "prettier" => "2.8.6" }))
        .to eq(content.sub('"2.8.0"', '"2.8.6"'))
    end
  end

  it "preserves mixed YAML line endings around a catalog edit" do
    content = "\uFEFF# 🎨 Catalog ranges\r\nnodeLinker: node-modules\rcatalog:\n  prettier: \"2.8.0\" # keep\r"
    catalogs.config_file.content = content
    expect(updater.updated_content).to eq(content.sub('"2.8.0"', '"^2.8.6"'))
  end

  [
    "\uFEFF{catalog: {prettier: \"2.8.0\"}}\n",
    "\uFEFF{label: '🎨', catalog: {prettier: \"2.8.0\"}}\r\n"
  ].each_with_index do |content, index|
    it "preserves the leading BOM and source offsets in configuration layout #{index + 1}" do
      catalogs.config_file.content = content
      expect(updater.updated_content).to eq(content.sub('"2.8.0"', '"^2.8.6"'))
      expect(updater.updated_content(pins: { "prettier" => "2.8.6" }))
        .to eq(content.sub('"2.8.0"', '"2.8.6"'))
    end
  end

  it "preserves unrelated aliases to anchored mapping keys while editing a catalog value" do
    catalogs.config_file.content = <<~YAML
      catalog:
        prettier: "2.8.0"
      &message enableMessageNames: true
      logFilters:
        - text: *message
          level: discard
    YAML
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
  end

  it "preserves unrelated duplicate keys under Yarn's last-value-wins schema" do
    catalogs.config_file.content += "enableMessageNames: false\nenableMessageNames: true\n"
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
  end

  it "treats an unused catalog named << as a literal key instead of a merged mapping" do
    catalogs.config_file.content = <<~YAML
      catalogs:
        "<<":
          prettier: 1.19.1
        formatting:
          prettier: "2.8.0"
    YAML
    files.select { |file| file.name.end_with?("package.json") }.each do |file|
      file.content = file.content.gsub("catalog:", "catalog:formatting")
    end
    requirement[:metadata][:yarn_catalog_reference] = "catalog:formatting"
    expect(updater.updated_content).to eq(catalogs.config_file.content.sub('"2.8.0"', '"^2.8.6"'))
  end

  context "when the selected value is a shared alias" do
    before do
      file = files.find { |candidate| candidate.name == ".yarnrc.yml" }
      file.content = file.content.sub("# Shared formatting version", "sharedVersion: &version 2.8.0")
                         .sub('"2.8.0"', "*version")
    end

    it "rejects the ambiguous edit instead of changing the shared definition" do
      expect { updater.updated_content }.to raise_error(Dependabot::ToolFeatureNotSupported, /scalar/)
    end
  end

  context "with an ambiguous selected mapping" do
    it "rejects an anchored selected scalar even when its aliases are unrelated to catalog consumers" do
      catalogs.config_file.content = <<~YAML
        catalog:
          prettier: &version "2.8.0"
        logFilters:
          - text: *version
            level: discard
      YAML
      expect { updater.updated_content }.to raise_error(Dependabot::ToolFeatureNotSupported, /scalar/)
    end

    it "rejects duplicate keys before editing" do
      catalogs.config_file.content = catalogs.config_file.content.sub("catalog:\n", "catalog:\n  prettier: 2.8.0\n")
      expect { updater.updated_content }.to raise_error(Dependabot::ToolFeatureNotSupported, /scalar/)
    end

    it "rejects a selected anchored mapping whose edit could alter an unrelated alias" do
      catalogs.config_file.content = catalogs.config_file.content.sub("catalog:\n", "catalog: &shared\n") +
                                     "other: *shared\n"
      expect { updater.updated_content }.to raise_error(Dependabot::ToolFeatureNotSupported, /scalar/)
    end
  end
end
