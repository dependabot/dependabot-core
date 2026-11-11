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

      it "does not infer Yarn from a nested project's lockfile" do
        files.find { |file| file.name == "yarn.lock" }.name = "packages/child/yarn.lock"
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

  ["../.yarnrc.yml", "packages/child/.yarnrc.yml"].each do |name|
    it "ignores #{name} when the project root configuration is missing" do
      config.name = name
      expect(catalogs.config_file).to be_nil
      expect { catalogs.bindings }.to raise_error(Dependabot::DependencyFileNotResolvable, /configuration/)
    end
  end

  it "uses the root configuration even if a nested configuration appears first" do
    files.unshift(Dependabot::DependencyFile.new(name: "packages/child/.yarnrc.yml", content: "invalid: [\n"))
    expect(catalogs.config_file).to eq(config)
    expect(catalogs.helper_catalogs).to eq("catalog:" => { "prettier" => "2.8.0" })
  end

  it "uses the root lockfile even if a nested lockfile appears first" do
    files.unshift(Dependabot::DependencyFile.new(name: "packages/child/yarn.lock", content: "invalid: [\n"))
    expect(catalogs.lockfile_details(catalogs.bindings.first).resolution).to eq("prettier@npm:2.8.0")
  end

  it "does not read a nested lockfile when the root lockfile is missing" do
    files.find { |file| file.name == "yarn.lock" }.name = "packages/child/yarn.lock"
    expect(catalogs.lockfile_details(catalogs.bindings.first)).to be_nil
    expect { catalogs.validate_update!("prettier") }.to raise_error(Dependabot::ToolFeatureNotSupported, /project root/)
  end

  %w(optionalDependencies peerDependencies).each do |group|
    it "inventories and rejects catalog consumption in #{group}" do
      child.content = child.content.sub('"dependencies"', group.to_json)
      expect(catalogs.bindings.first.groups).to include(group)
      expect { catalogs.validate_update!("prettier") }.to raise_error(Dependabot::ToolFeatureNotSupported, /#{group}/)
    end
  end

  it "rejects peer-only catalog consumption" do
    root.content = root.content.sub('"devDependencies"', '"peerDependencies"')
    child.content = child.content.sub('"dependencies"', '"peerDependencies"')
    expect(catalogs.bindings.first.groups).to eq(["peerDependencies"])
    expect { catalogs.validate_update!("prettier") }
      .to raise_error(Dependabot::ToolFeatureNotSupported, /peerDependencies/)
  end

  it "allows ordinary peer declarations alongside catalog development dependencies" do
    child.content = child.content.sub('"dependencies"', '"peerDependencies"').sub("catalog:", "^2.8.0")
    expect { catalogs.validate_update!("prettier") }.not_to raise_error
  end

  it "rejects the same package consumed through multiple catalogs" do
    child.content = child.content.sub("catalog:", "catalog:unused")
    expect(catalogs.bindings.map(&:reference)).to eq(["catalog:", "catalog:unused"])
    expect { catalogs.validate_update!("prettier") }
      .to raise_error(Dependabot::ToolFeatureNotSupported, /multiple catalog bindings/)
  end

  %w(
    workspace:* npm:prettier@2.8.0 latest git+https://example.com/prettier.git file:../prettier ../prettier
  ).each do |range|
    it "rejects the non-registry catalog requirement #{range}" do
      config.content = "catalog: {prettier: #{range.to_json}}\n"
      expect { catalogs.validate_update!("prettier") }
        .to raise_error(Dependabot::ToolFeatureNotSupported, /non-registry/)
    end
  end

  it "fails the inventory for a dangling optional reference even when other bindings are valid" do
    child.content = JSON.generate("optionalDependencies" => { "missing" => "catalog:" })
    expect { catalogs.bindings }
      .to raise_error(Dependabot::DependencyFileNotResolvable, /missing@catalog:.*entry missing/)
  end

  context "when a catalog range resolves to a local workspace" do
    let(:files) { project_dependency_files("yarn_berry/catalog_local_workspace") }

    it "matches the generated npm descriptor and rejects the update" do
      binding = catalogs.bindings.first
      expect(catalogs.lockfile_details(binding).resolution).to eq("prettier@workspace:packages/child")
      expect(catalogs.workspace_dependency?(binding)).to be(true)
      expect { catalogs.validate_update!("prettier") }
        .to raise_error(Dependabot::ToolFeatureNotSupported, /local workspace/)
    end
  end

  describe "#validate_yarn_version!" do
    %w(4.9.9 4.10.0-rc.1).each do |version|
      it "rejects Yarn #{version} without native catalog support" do
        expect { catalogs.validate_yarn_version!(version) }
          .to raise_error(Dependabot::ToolFeatureNotSupported, /native catalogs/)
      end
    end

    %w(4.10.0 4.10.1 5.0.0).each do |version|
      it "accepts Yarn #{version} with native catalog support" do
        expect { catalogs.validate_yarn_version!(version) }.not_to raise_error
      end
    end
  end
end
