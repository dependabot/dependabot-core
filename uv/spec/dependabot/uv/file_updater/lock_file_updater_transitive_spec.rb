# typed: true
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

  # A plain requirements file (not managed by uv) can list a package that uv.lock holds as a dependency of a
  # pyproject.toml dependency, for example `pandas` below `streamlit`.
  describe "#updated_dependency_files for a dependency declared only in requirements.txt" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:requirements_file) { Dependabot::DependencyFile.new(name: "requirements.txt", content: requirements_content) }
    let(:dependency_files) { [pyproject_file, lockfile, requirements_file] }
    let(:requirements_content) { "requests\ncertifi\n" }
    let(:old_requirement) { nil }
    let(:new_requirement) { nil }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "2025.1.31",
        previous_version: "2024.07.04",
        requirements: [{ file: "requirements.txt", requirement: new_requirement, groups: ["dependencies"],
                         source: nil }],
        previous_requirements: [
          { file: "requirements.txt", requirement: old_requirement, groups: ["dependencies"], source: nil }
        ],
        package_manager: "uv"
      )
    end
    let(:dependency_name) { "certifi" }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("success")
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
      allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
      allow(File).to receive(:write).and_return(100)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("uv.lock").and_return("updated lock content")

      lvm = instance_double(Dependabot::Uv::LanguageVersionManager)
      allow(Dependabot::Uv::LanguageVersionManager).to receive(:new).and_return(lvm)
      allow(lvm).to receive(:install_required_python)
      allow(lvm).to receive(:python_version).and_return("3.9")
    end

    it "updates uv.lock, where the dependency is locked" do
      expect(updated_files.map(&:name)).to eq(["uv.lock"])
      expect(updated_files.first.content).to eq("updated lock content")
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
        .with(a_string_including("uv lock --upgrade-package certifi==2025.1.31"), anything)
    end

    context "when its requirement in requirements.txt changes" do
      let(:old_requirement) { "==2024.07.04" }
      let(:new_requirement) { "==2025.1.31" }

      it "updates nothing, since the requirements file would not match the lock" do
        expect(updated_files).to eq([])
      end
    end

    context "when uv.lock does not hold the dependency" do
      let(:dependency_name) { "pandas" }

      it "updates nothing" do
        expect(updated_files).to eq([])
      end
    end
  end
end
