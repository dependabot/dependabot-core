# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/pnpm_resolutions"

RSpec.describe Dependabot::NpmAndYarn::PnpmResolutions do
  let(:v6_lockfile) do
    <<~YAML
      lockfileVersion: '6.0'

      importers:

        packages/app:
          dependencies:
            react:
              specifier: ^18.0.0
              version: 18.2.0

      packages:

        /a@1.0.0:
          resolution: {integrity: sha512-a==}
          dependencies:
            react: 18.2.0

        /b@1.0.0:
          resolution: {integrity: sha512-b==}
          dependencies:
            react: 17.0.2

        /c@1.0.0:
          resolution: {integrity: sha512-c==}
          dependencies:
            react-dom: 18.2.0(react@18.2.0)
    YAML
  end

  let(:v9_lockfile) do
    <<~YAML
      ---
      lockfileVersion: '9.0'
      importers:
        .:
          packageManagerDependencies:
            pnpm:
              specifier: 12.2.1
              version: 12.2.1
      ---
      lockfileVersion: '9.0'

      importers:

        .:
          devDependencies:
            react:
              specifier: ^18.0.0
              version: 18.2.0

      snapshots:

        a@1.0.0:
          dependencies:
            react: 18.2.0

        c@1.0.0:
          dependencies:
            react-dom: 18.2.0(react@18.2.0)
    YAML
  end

  describe "#edges" do
    it "lists every dependent's resolution in a v6 lockfile" do
      expect(described_class.new(v6_lockfile).edges("react")).to eq(
        "importers/packages/app/dependencies" => "18.2.0",
        "packages//a@1.0.0/dependencies" => "18.2.0",
        "packages//b@1.0.0/dependencies" => "17.0.2"
      )
    end

    it "reads the project document of a v9 stream and drops peer suffixes" do
      resolutions = described_class.new(v9_lockfile)

      expect(resolutions.edges("react")).to eq(
        "importers/./devDependencies" => "18.2.0",
        "snapshots/a@1.0.0/dependencies" => "18.2.0"
      )
      expect(resolutions.edges("react-dom")).to eq("snapshots/c@1.0.0/dependencies" => "18.2.0")
    end
  end

  describe ".changed_versions" do
    it "reports an edge moved onto a version that was already present elsewhere" do
      after = v6_lockfile.sub("react: 17.0.2", "react: 18.2.0")

      expect(described_class.changed_versions(v6_lockfile, after, "react")).to eq(["18.2.0"])
    end

    it "reports nothing when every edge is unchanged" do
      expect(described_class.changed_versions(v6_lockfile, v6_lockfile, "react")).to eq([])
    end
  end

  describe "#importers" do
    def importers_of(content) = described_class.new(content).importers

    it "lists the importer paths the lockfile records" do
      expect(importers_of(v6_lockfile)).to eq(["packages/app"])
    end

    it "reads the last document, since pnpm 11 can write an env document first" do
      content = "env:\n  NODE_ENV: production\n---\n" \
                "lockfileVersion: '9.0'\nimporters:\n  .: {}\n  packages/a: {}\n"

      expect(importers_of(content)).to eq([".", "packages/a"])
    end

    # Psych loads plain scalars on the YAML 1.1 schema, where these spellings are
    # booleans, nil or integers rather than the directory names pnpm wrote.
    it "keeps directory names YAML 1.1 would resolve to something else" do
      content = "lockfileVersion: '9.0'\nimporters:\n" \
                "  no: {}\n  on: {}\n  yes: {}\n  10: {}\n  packages/ok: {}\n"

      expect(importers_of(content)).to eq(%w(no on yes 10 packages/ok))
    end

    it "answers with nothing when there is no importers section" do
      expect(importers_of("lockfileVersion: '9.0'\npackages: {}\n")).to eq([])
    end

    it "raises on a lockfile that cannot be parsed, as the other readers do" do
      expect { importers_of("importers: [\n") }.to raise_error(Psych::SyntaxError)
    end
  end
end
