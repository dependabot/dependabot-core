# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/pnpm_workspace_includes"

RSpec.describe Dependabot::NpmAndYarn::PnpmWorkspaceIncludes do
  def workspace_file(content, name: "pnpm-workspace.yaml")
    Dependabot::DependencyFile.new(name: name, content: content)
  end

  describe ".included_file_paths" do
    subject(:paths) { described_class.included_file_paths(file) }

    context "with a catalog file included from the workspace root" do
      let(:file) { workspace_file("packages:\n  - packages/*\n\ninclude:\n  ./pnpm-catalogs.yaml: [catalogs]\n") }

      it { is_expected.to eq(["pnpm-catalogs.yaml"]) }
    end

    context "with several local files, a config dependency and a non-YAML source" do
      let(:file) do
        workspace_file(<<~YAML)
          configDependencies:
            '@acme/pnpm-policy': 3.1.0
          include:
            ./config/security.yaml: '*'
            ./config/catalog.yml: [catalog]
            ../shared/pnpm.yaml: [overrides]
            '@acme/pnpm-policy': [minimumReleaseAge]
            ./config/settings.json: [nodeLinker]
        YAML
      end

      it "returns only the local YAML files, resolved from the workspace root" do
        expect(paths).to eq(["config/security.yaml", "config/catalog.yml", "../shared/pnpm.yaml"])
      end
    end

    context "when the workspace file was fetched from a parent directory" do
      let(:file) { workspace_file("include:\n  ./pnpm-catalogs.yaml: [catalog]\n", name: "../../pnpm-workspace.yaml") }

      it "resolves the included file next to it" do
        expect(paths).to eq(["../../pnpm-catalogs.yaml"])
      end
    end

    context "without an include mapping" do
      let(:file) { workspace_file("packages:\n  - packages/*\ninclude: ./pnpm-catalogs.yaml\n") }

      it { is_expected.to eq([]) }
    end

    context "when the workspace file is not a mapping" do
      let(:file) { workspace_file("# only a comment\n") }

      it { is_expected.to eq([]) }
    end

    context "when the workspace file is not valid YAML" do
      let(:file) { workspace_file("include:\n  ./pnpm-catalogs.yaml: [catalog\n") }

      it { is_expected.to eq([]) }
    end
  end

  describe ".included_files" do
    subject(:included) { described_class.included_files(files) }

    let(:catalogs) { Dependabot::DependencyFile.new(name: "pnpm-catalogs.yaml", content: "catalog:\n  a: 1.0.0\n") }
    let(:unrelated) { Dependabot::DependencyFile.new(name: "other.yaml", content: "catalog:\n  b: 1.0.0\n") }
    let(:files) do
      [
        Dependabot::DependencyFile.new(name: "package.json", content: "{}"),
        workspace_file("include:\n  ./pnpm-catalogs.yaml: [catalog]\n"),
        catalogs,
        unrelated
      ]
    end

    it "returns the dependency files that pnpm-workspace.yaml includes" do
      expect(included).to eq([catalogs])
    end

    context "without a pnpm-workspace.yaml" do
      let(:files) { [catalogs, unrelated] }

      it { is_expected.to eq([]) }
    end
  end
end
