# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/file_updater/lock_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Uv::FileUpdater::LockFileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: credentials,
      index_urls: index_urls
    )
  end

  let(:dependencies) { [dependency] }
  let(:credentials) { [] }
  let(:index_urls) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "certifi", # Transitive dependency
      version: "2025.1.31",
      requirements: [], # No requirements in pyproject.toml
      previous_requirements: [],
      previous_version: "2024.07.04",
      package_manager: "uv"
    )
  end

  let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }
  let(:lockfile_content) { fixture("uv_locks", "simple.lock") }

  let(:pyproject_file) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "uv.lock",
      content: lockfile_content
    )
  end

  let(:dependency_files) { [pyproject_file, lockfile] }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("success")
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
      allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
      allow(File).to receive(:write).and_return(100)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("uv.lock").and_return("updated lock content")

      # Mock LanguageVersionManager
      lvm = instance_double(Dependabot::Uv::LanguageVersionManager)
      allow(Dependabot::Uv::LanguageVersionManager).to receive(:new).and_return(lvm)
      allow(lvm).to receive(:install_required_python)
      allow(lvm).to receive(:python_version).and_return("3.9")
    end

    it "updates the lockfile for transitive dependency" do
      expect(updated_files.count).to eq(1)
      expect(updated_files.first.name).to eq("uv.lock")
    end
  end
end
