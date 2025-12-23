# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/lean/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Lean::FileUpdater do
  let(:files) { [lean_toolchain] }
  let(:lean_toolchain) do
    Dependabot::DependencyFile.new(
      name: "lean-toolchain",
      content: lean_toolchain_content
    )
  end
  let(:lean_toolchain_content) { "leanprover/lean4:v4.26.0\n" }
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "lean4",
      version: "4.27.0",
      previous_version: "4.26.0",
      requirements: [{
        requirement: "4.27.0",
        file: "lean-toolchain",
        groups: [],
        source: { type: "default" }
      }],
      previous_requirements: [{
        requirement: "4.26.0",
        file: "lean-toolchain",
        groups: [],
        source: { type: "default" }
      }],
      package_manager: "lake"
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: [],
      repo_contents_path: nil
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns one updated file" do
      expect(updated_files.count).to eq(1)
    end

    it "updates the version in lean-toolchain" do
      expect(updated_files.first.content).to eq("leanprover/lean4:v4.27.0\n")
    end

    context "when updating to an RC version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lean4",
          version: "4.28.0-rc1",
          previous_version: "4.27.0",
          requirements: [{
            requirement: "4.28.0-rc1",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }],
          previous_requirements: [{
            requirement: "4.27.0",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }],
          package_manager: "lake"
        )
      end
      let(:lean_toolchain_content) { "leanprover/lean4:v4.27.0\n" }

      it "updates to the RC version" do
        expect(updated_files.first.content).to eq("leanprover/lean4:v4.28.0-rc1\n")
      end
    end

    context "when updating from an RC version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lean4",
          version: "4.27.0",
          previous_version: "4.27.0-rc2",
          requirements: [{
            requirement: "4.27.0",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }],
          previous_requirements: [{
            requirement: "4.27.0-rc2",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }],
          package_manager: "lake"
        )
      end
      let(:lean_toolchain_content) { "leanprover/lean4:v4.27.0-rc2\n" }

      it "updates from RC to stable" do
        expect(updated_files.first.content).to eq("leanprover/lean4:v4.27.0\n")
      end
    end
  end
end
