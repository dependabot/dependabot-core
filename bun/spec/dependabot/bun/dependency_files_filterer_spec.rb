# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/dependency_files_filterer"

RSpec.describe Dependabot::Bun::DependencyFilesFilterer do
  subject(:filterer) do
    described_class.new(dependency_files: files, updated_dependencies: [dependency])
  end

  let(:workspaces) { [] }
  let(:root_content) { JSON.dump("workspaces" => workspaces, "dependencies" => []) }
  let(:root_manifest) { Dependabot::DependencyFile.new(name: "package.json", content: root_content) }
  let(:member_manifest) do
    Dependabot::DependencyFile.new(name: "packages/member/package.json", content: "{}")
  end
  let(:root_lockfile) { Dependabot::DependencyFile.new(name: "bun.lock", content: "{}") }
  let(:files) { [root_manifest, member_manifest, root_lockfile] }
  let(:requirement_file) { member_manifest.name }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "chalk",
      version: "0.4.0",
      requirements: [{
        file: requirement_file,
        requirement: "0.3.0",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "bun"
    )
  end

  before do
    lockfile_parser = instance_double(Dependabot::Bun::FileParser::LockfileParser, parse: [dependency])
    allow(Dependabot::Bun::FileParser::LockfileParser).to receive(:new).and_return(lockfile_parser)
  end

  it "selects the member manifest and workspace lockfile without reading dependency values" do
    expect(filterer.files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
  end

  it "returns the manifests requiring an update" do
    expect(filterer.package_files_requiring_update).to eq([member_manifest])
  end

  it "checks the root path when a single root lockfile tracks all dependencies" do
    expect(filterer.paths_requiring_update_check).to eq(["."])
  end

  context "with an object workspace declaration" do
    let(:workspaces) { {} }

    it "keeps the root lockfile" do
      expect(filterer.files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
    end
  end

  [nil, false].each do |value|
    context "with workspaces set to #{value.inspect}" do
      let(:workspaces) { value }

      it "does not treat the root lockfile as a workspace lockfile" do
        expect(filterer.files_requiring_update).to eq([member_manifest])
      end
    end
  end

  context "with a pnpm workspace file" do
    let(:workspaces) { nil }
    let(:files) { super() + [Dependabot::DependencyFile.new(name: "pnpm-workspace.yaml", content: "packages: []")] }

    it "retains the existing workspace fallback" do
      expect(filterer.files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
    end
  end

  context "with a root dependency" do
    let(:requirement_file) { root_manifest.name }
    let(:root_content) { "{" }

    it "keeps the associated lockfile without parsing unrelated workspace information" do
      expect(filterer.files_requiring_update).to contain_exactly(root_manifest, root_lockfile)
    end
  end

  context "with a nested lockfile and no root manifest" do
    let(:root_lockfile) { Dependabot::DependencyFile.new(name: "packages/member/bun.lock", content: "{}") }
    let(:files) { [member_manifest, root_lockfile] }

    it "selects the nested files without reading a root manifest" do
      expect(filterer.files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
      expect(filterer.paths_requiring_update_check).to eq(["packages/member"])
    end
  end

  context "with a root shrinkwrap" do
    let(:root_lockfile) { Dependabot::DependencyFile.new(name: "npm-shrinkwrap.json", content: "{}") }

    it "does not add npm-only workspace shrinkwrap behavior" do
      expect(filterer.files_requiring_update).to eq([member_manifest])
    end
  end

  context "with multiple workspace lockfiles" do
    let(:other_lockfile) { Dependabot::DependencyFile.new(name: "yarn.lock", content: "") }
    let(:files) { super() + [other_lockfile] }

    it "decodes the root manifest once" do
      allow(JSON).to receive(:parse).and_call_original

      expect(filterer.files_requiring_update).to contain_exactly(member_manifest, root_lockfile, other_lockfile)
      expect(JSON).to have_received(:parse).with(root_content).once
    end
  end
end
