# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/yarn_catalogs"

RSpec.describe Dependabot::NpmAndYarn::YarnCatalogs do
  let(:files) { project_dependency_files("yarn_berry/catalog_workspace") }
  let(:catalogs) { described_class.new(dependency_files: files) }
  let(:config) { files.find { |file| file.name == ".yarnrc.yml" } }
  let(:root) { files.find { |file| file.name == "package.json" } }
  let(:child) { files.find { |file| file.name == "packages/child/package.json" } }

  describe ".parse_configuration" do
    it "preserves aliases to unrelated anchored mapping keys" do
      content = <<~YAML
        catalog:
          prettier: "2.8.0"
        &message enableMessageNames: true
        logFilters:
          - text: *message
            level: discard
      YAML
      expect(described_class.parse_configuration(content)).to eq(
        "catalog" => { "prettier" => "2.8.0" },
        "enableMessageNames" => "true",
        "logFilters" => [{ "text" => "enableMessageNames", "level" => "discard" }]
      )
    end

    it "accepts failsafe tags matching their scalar and collection kinds" do
      content = "!!map {catalog: !!map {prettier: !!str 2.8}, logFilters: !!seq []}\n"
      expect(described_class.parse_configuration(content)).to eq(
        "catalog" => { "prettier" => "2.8" }, "logFilters" => []
      )
    end

    [
      'catalog: {prettier: !!map "2.8.0"}',
      'catalog: {prettier: !!seq "2.8.0"}',
      'catalog: !!str {prettier: "2.8.0"}',
      "catalog: {prettier: !!int 2}"
    ].each do |content|
      it "rejects unsupported node tags in #{content}" do
        expect { described_class.parse_configuration(content) }
          .to raise_error(Dependabot::DependencyFileNotParseable, /configuration tag/)
      end
    end

    it "rejects multiple documents instead of inventorying only the first" do
      content = "catalog: {prettier: 2.8.0}\n---\ncatalog: {prettier: 2.8.6}\n"
      expect { described_class.parse_configuration(content) }
        .to raise_error(Dependabot::DependencyFileNotParseable, /single YAML document/)
    end
  end

  describe "package manager selection" do
    %w(npm@11.0.0 pnpm@10.0.0).each do |pin|
      it "ignores Yarn artifacts and configuration when the root pins #{pin}" do
        root.content = root.content.sub("yarn@4.10.1", pin)
        config.content = "invalid: [\n"
        expect(catalogs.bindings).to eq([])
      end
    end

    context "without a packageManager pin" do
      before do
        root.content = JSON.generate(JSON.parse(root.content).except("packageManager"))
      end

      it "inventories consumed bindings in a Yarn-only project" do
        expect(catalogs.helper_catalogs).to eq("catalog:" => { "prettier" => "2.8.0" })
      end

      it "does not infer Yarn from catalog declarations without a lockfile" do
        files.reject! { |file| file.name == "yarn.lock" }
        expect(catalogs.bindings).to eq([])
      end

      %w(package-lock.json npm-shrinkwrap.json pnpm-lock.yaml pnpm-workspace.yaml).each do |name|
        it "does not infer Yarn when #{name} also identifies a package manager project" do
          files << Dependabot::DependencyFile.new(name: name, content: "{}")
          config.content = "invalid: [\n"
          expect(catalogs.bindings).to eq([])
        end
      end
    end

    it "retains explicitly pinned Yarn inventory but rejects updates with competing manager projects" do
      files << Dependabot::DependencyFile.new(name: "package-lock.json", content: "{}")
      expect(catalogs.helper_catalogs).to eq("catalog:" => { "prettier" => "2.8.0" })
      expect { catalogs.validate_update!("prettier") }
        .to raise_error(Dependabot::ToolFeatureNotSupported, /multiple package manager projects/)
    end
  end

  it "retains child-only development consumption and does not inventory unused definitions" do
    root.content = root.content.sub('"prettier": "catalog:"', '"other": "*"')
    child.content = child.content.sub('"dependencies"', '"devDependencies"')
    expect(
      catalogs.bindings.map do |binding|
        [binding.name, binding.groups]
      end
    ).to eq([["prettier", ["devDependencies"]]])
    expect(catalogs.helper_catalogs).to eq("catalog:" => { "prettier" => "2.8.0" })
  end

  it "reports a missing configuration as a resolution error" do
    files.delete(config)
    expect { catalogs.bindings }.to raise_error(Dependabot::DependencyFileNotResolvable, /configuration/)
  end

  it "rejects catalog and ordinary direct declarations of the same package" do
    child.content = child.content.sub("catalog:", "2.8.0")
    expect { catalogs.validate_update!("prettier") }.to raise_error(Dependabot::ToolFeatureNotSupported, /ordinary/)
  end

  it "retains inherited configuration identity but rejects editing outside the project root" do
    config.name = "../.yarnrc.yml"
    expect(catalogs.bindings.first.reference).to eq("catalog:")
    expect { catalogs.validate_update!("prettier") }.to raise_error(Dependabot::ToolFeatureNotSupported, /project root/)
  end
end
