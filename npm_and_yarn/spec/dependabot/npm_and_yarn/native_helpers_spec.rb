# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"

RSpec.describe Dependabot::NpmAndYarn::NativeHelpers do
  describe ".npm_subdependency_update_allowed?" do
    subject(:allowed) do
      described_class.npm_subdependency_update_allowed?(
        lockfile: lockfile,
        updated_content: updated_content,
        dependency: dependency,
        ignored_versions: ignored_versions
      )
    end

    let(:dependency) do
      Dependabot::Dependency.new(name: "child", version: "1.2.0", requirements: [], package_manager: "npm_and_yarn")
    end
    let(:ignored_versions) { [] }
    let(:original_packages) do
      {
        "node_modules/child" => { "version" => "1.0.0" },
        "node_modules/parent/node_modules/child" => { "version" => "2.0.0" }
      }
    end
    let(:updated_packages) { original_packages.merge("node_modules/child" => { "version" => "1.2.0" }) }
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "package-lock.json", content: JSON.generate(lockfileVersion: 3, packages: original_packages)
      )
    end
    let(:updated_content) { JSON.generate(lockfileVersion: 3, packages: updated_packages) }

    it "accepts the bound and leaves an unchanged higher occurrence alone" do
      expect(allowed).to be(true)
    end

    context "when a nested occurrence exceeds the bound" do
      let(:updated_packages) do
        super().merge("node_modules/parent/node_modules/child" => { "version" => "2.1.0" })
      end

      it { is_expected.to be(false) }
    end

    context "when npm adds an aliased occurrence above the bound" do
      let(:updated_packages) do
        super().merge("node_modules/@scope/alias" => { "name" => "child", "version" => "2.0.0" })
      end

      it { is_expected.to be(false) }
    end

    context "when an ignored range is below the upper bound" do
      let(:ignored_versions) { [">= 1.1.0, < 1.3.0"] }

      it { is_expected.to be(false) }
    end

    context "when only unchanged occurrences match an ignore rule" do
      let(:ignored_versions) { [">= 2"] }

      it { is_expected.to be(true) }
    end

    context "when an updated occurrence has no valid version" do
      let(:updated_packages) { super().merge("node_modules/child" => { "version" => "not-semver" }) }

      it { is_expected.to be(false) }
    end

    context "with a v2 lockfile containing a stale legacy section" do
      let(:updated_content) do
        JSON.generate(
          lockfileVersion: 2,
          packages: updated_packages,
          dependencies: { child: { version: "1.0.0" } }
        )
      end
      let(:updated_packages) { super().merge("node_modules/child" => { "version" => "1.3.0" }) }

      it { is_expected.to be(false) }
    end
  end

  describe ".run_pnpm_audit_fix_command" do
    before do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command) do |command, **|
        command == "-v" ? pnpm_version : ""
      end
    end

    context "with pnpm 11" do
      let(:pnpm_version) { "Corepack warning\n11.25.0\n" }

      it "uses the lockfile update fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix=update", fingerprint: "audit --fix=update")
      end
    end

    context "with pnpm 10" do
      let(:pnpm_version) { "10.16.0" }

      it "uses the compatible override fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix", fingerprint: "audit --fix")
      end
    end
  end
end
