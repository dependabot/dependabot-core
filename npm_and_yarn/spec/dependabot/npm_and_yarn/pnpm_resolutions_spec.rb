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
end
