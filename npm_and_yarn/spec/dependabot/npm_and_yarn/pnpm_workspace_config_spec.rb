# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/pnpm_workspace_config"

RSpec.describe Dependabot::NpmAndYarn::PnpmWorkspaceConfig do
  subject(:lockfile_per_project) { described_class.lockfile_per_project?(files) }

  def workspace(content)
    Dependabot::DependencyFile.new(name: "pnpm-workspace.yaml", content: content)
  end

  def npmrc(content)
    Dependabot::DependencyFile.new(name: ".npmrc", content: content)
  end

  context "when nothing in the repository mentions the setting" do
    let(:files) { [workspace("packages:\n  - ./packages/*\n"), npmrc("registry=https://example.com\n")] }

    it { is_expected.to be(false) }
  end

  context "when no files are given at all" do
    let(:files) { [] }

    it { is_expected.to be(false) }
  end

  describe "pnpm-workspace.yaml" do
    context "when it disables the shared lockfile" do
      let(:files) { [workspace("packages:\n  - ./packages/*\n\nsharedWorkspaceLockfile: false\n")] }

      it { is_expected.to be(true) }
    end

    context "when it enables the shared lockfile" do
      let(:files) { [workspace("sharedWorkspaceLockfile: true\n")] }

      it { is_expected.to be(false) }
    end

    context "when the mapping is written in flow style" do
      let(:files) { [workspace("{ packages: ['packages/*'], sharedWorkspaceLockfile: false }\n")] }

      it { is_expected.to be(true) }
    end

    context "when the value is quoted" do
      let(:files) { [workspace("sharedWorkspaceLockfile: 'false'\n")] }

      it { is_expected.to be(true) }
    end

    context "when a comment follows the value" do
      let(:files) { [workspace("sharedWorkspaceLockfile: false # one lockfile each\n")] }

      it { is_expected.to be(true) }
    end

    context "when it uses the kebab-case spelling pnpm ignores there" do
      let(:files) { [workspace("shared-workspace-lockfile: false\n")] }

      it { is_expected.to be(false) }
    end

    context "when the file cannot be parsed" do
      let(:files) { [workspace("packages: [\n")] }

      it { is_expected.to be(false) }
    end

    context "when the file is not a mapping" do
      let(:files) { [workspace("- just\n- a list\n")] }

      it { is_expected.to be(false) }
    end
  end

  describe ".npmrc" do
    context "when it disables the shared lockfile" do
      let(:files) { [npmrc("shared-workspace-lockfile=false\n")] }

      it { is_expected.to be(true) }
    end

    context "when it enables the shared lockfile" do
      let(:files) { [npmrc("shared-workspace-lockfile=true\n")] }

      it { is_expected.to be(false) }
    end

    context "when a later line overrides an earlier one" do
      let(:files) { [npmrc("shared-workspace-lockfile=false\nshared-workspace-lockfile=true\n")] }

      it { is_expected.to be(false) }
    end

    context "when a semicolon comment follows the value" do
      let(:files) { [npmrc("shared-workspace-lockfile=false ; one each\n")] }

      it { is_expected.to be(true) }
    end

    context "when it uses the camelCase spelling pnpm ignores there" do
      let(:files) { [npmrc("sharedWorkspaceLockfile=false\n")] }

      it { is_expected.to be(false) }
    end
  end

  describe ".declared_in_workspace_yaml?" do
    subject(:declared) { described_class.declared_in_workspace_yaml?(files) }

    context "when only .npmrc disables it" do
      let(:files) { [npmrc("shared-workspace-lockfile=false\n")] }

      it "does not answer for a file pnpm stopped reading in 11" do
        expect(declared).to be(false)
      end
    end

    context "when pnpm-workspace.yaml disables it" do
      let(:files) { [workspace("sharedWorkspaceLockfile: false\n")] }

      it { is_expected.to be(true) }
    end
  end

  describe ".declared_in_npmrc?" do
    subject(:declared) { described_class.declared_in_npmrc?(files) }

    context "when only pnpm-workspace.yaml disables it" do
      let(:files) { [workspace("sharedWorkspaceLockfile: false\n")] }

      it { is_expected.to be(false) }
    end

    context "when .npmrc disables it" do
      let(:files) { [npmrc("shared-workspace-lockfile=false\n")] }

      it { is_expected.to be(true) }
    end
  end

  context "when a nested project disables it" do
    let(:files) do
      [Dependabot::DependencyFile.new(
        name: "packages/package1/.npmrc",
        content: "shared-workspace-lockfile=false\n"
      )]
    end

    it { is_expected.to be(true) }
  end
end
