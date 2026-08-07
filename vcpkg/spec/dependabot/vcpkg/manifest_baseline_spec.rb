# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency_file"
require "dependabot/vcpkg/manifest_baseline"

RSpec.describe Dependabot::Vcpkg::ManifestBaseline do
  subject(:baseline) { described_class.new(dependency_files: dependency_files) }

  let(:sha) { "fe1cde61e971d53c9687cf9a46308f8f55da19fa" }

  def manifest(content)
    Dependabot::DependencyFile.new(name: "vcpkg.json", content: content)
  end

  def configuration(content)
    Dependabot::DependencyFile.new(name: "vcpkg-configuration.json", content: content)
  end

  context "with a builtin-baseline in the manifest" do
    let(:dependency_files) { [manifest(%({ "builtin-baseline": "#{sha}" }))] }

    it "returns the pinned commit" do
      expect(baseline.ref).to eq(sha)
    end

    it "reports where to rewrite it" do
      expect(baseline.location).to eq(["vcpkg.json", ["builtin-baseline"]])
    end
  end

  context "with a builtin default registry in the configuration" do
    let(:dependency_files) do
      [
        manifest(%({ "dependencies": ["zlib"] })),
        configuration(%({ "default-registry": { "kind": "builtin", "baseline": "#{sha}" } }))
      ]
    end

    it "returns the pinned commit" do
      expect(baseline.ref).to eq(sha)
    end

    it "reports where to rewrite it" do
      expect(baseline.location).to eq(["vcpkg-configuration.json", %w(default-registry baseline)])
    end
  end

  context "with a git default registry pointing at the official repository" do
    let(:dependency_files) do
      [
        manifest(%({ "dependencies": ["zlib"] })),
        configuration(
          %({ "default-registry": { "kind": "git", "repository": "https://github.com/microsoft/vcpkg",
              "baseline": "#{sha}" } })
        )
      ]
    end

    it "returns the pinned commit" do
      expect(baseline.ref).to eq(sha)
    end
  end

  context "with a git default registry pointing somewhere else" do
    let(:dependency_files) do
      [
        manifest(%({ "dependencies": ["zlib"] })),
        configuration(
          %({ "default-registry": { "kind": "git", "repository": "https://example.com/registry",
              "baseline": "#{sha}" } })
        )
      ]
    end

    it "ignores the registry, because the shipped versions database does not describe it" do
      expect(baseline.ref).to be_nil
      expect(baseline.location).to be_nil
    end
  end

  context "when the manifest baseline wins over the configuration" do
    let(:dependency_files) do
      [
        manifest(%({ "builtin-baseline": "#{sha}" })),
        configuration(%({ "default-registry": { "kind": "builtin", "baseline": "#{'a' * 40}" } }))
      ]
    end

    it "prefers the manifest" do
      expect(baseline.ref).to eq(sha)
      expect(baseline.location).to eq(["vcpkg.json", ["builtin-baseline"]])
    end
  end

  context "with no baseline anywhere" do
    let(:dependency_files) { [manifest(%({ "dependencies": ["zlib"] }))] }

    it { expect(baseline.ref).to be_nil }
    it { expect(baseline.location).to be_nil }
  end

  context "with unparseable JSON" do
    let(:dependency_files) { [manifest("{ not json")] }

    it "does not raise" do
      expect(baseline.ref).to be_nil
    end
  end
end
