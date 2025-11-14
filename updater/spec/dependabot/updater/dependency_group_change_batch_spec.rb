# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/dependency_group_change_batch"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/job"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
  let(:manifest_path) { "/WorkspacePackage1.jl/Manifest.toml" }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: "name = \"SubPackageA\"",
        directory: "/WorkspacePackage1.jl/SubPackageA",
        associated_lockfile_path: manifest_path
      ),
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: "name = \"SubPackageB\"",
        directory: "/WorkspacePackage1.jl/SubPackageB",
        associated_lockfile_path: manifest_path
      ),
      Dependabot::DependencyFile.new(
        name: "Manifest.toml",
        content: "manifest",
        directory: "/WorkspacePackage1.jl",
        associated_manifest_paths: [
          "/WorkspacePackage1.jl/SubPackageA/Project.toml",
          "/WorkspacePackage1.jl/SubPackageB/Project.toml"
        ]
      )
    ]
  end
  let(:batch) { described_class.new(initial_dependency_files: dependency_files) }

  describe "#current_dependency_files" do
    it "includes sibling project files that share a lockfile" do
      source = Dependabot::Source.new(provider: "github", repo: "foo/bar", directory: "/WorkspacePackage1.jl/SubPackageA")
      job = instance_double(Dependabot::Job, source: source)

      files = batch.current_dependency_files(job)
      paths = files.map(&:path)

      expect(paths).to include("/WorkspacePackage1.jl/SubPackageA/Project.toml")
      expect(paths).to include("/WorkspacePackage1.jl/SubPackageB/Project.toml")
      expect(paths).to include("/WorkspacePackage1.jl/Manifest.toml")
    end
  end
end
