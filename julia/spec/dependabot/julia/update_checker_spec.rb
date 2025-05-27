# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/julia/update_checker"

RSpec.describe Dependabot::Julia::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Example",
      version: "0.5.5",
      requirements: [{
        file: "Project.toml",
        requirement: "0.4",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "julia"
    )
  end

  let(:dependency_files) { [project_file, manifest_file] }
  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "Project.toml",
      content: fixture("projects", "basic", "Project.toml")
    )
  end
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Manifest.toml",
      content: fixture("projects", "basic", "Manifest.toml")
    )
  end
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "delegates to VersionResolver" do
      expect(latest_version).to be_a(Dependabot::Julia::Version)
    end
  end
end
