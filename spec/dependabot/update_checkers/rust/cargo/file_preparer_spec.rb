# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/rust/cargo/file_preparer"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      unlock_requirement: unlock_requirement
    )
  end

  let(:dependency_files) { [manifest, lockfile] }
  let(:unlock_requirement) { true }

  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("rust", "manifests", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("rust", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:requirements) do
    [{
      file: "Cargo.toml",
      requirement: string_req,
      groups: [],
      source: source
    }]
  end
  let(:dependency_name) { "regex" }
  let(:dependency_version) { "0.1.41" }
  let(:string_req) { "0.1.41" }
  let(:source) { nil }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    its(:length) { is_expected.to eq(2) }

    describe "the updated Cargo.toml" do
      subject(:prepared_manifest_file) do
        prepared_dependency_files.find { |f| f.name == "Cargo.toml" }
      end

      context "with unlock_requirement set to false" do
        let(:unlock_requirement) { false }

        it "doesn't update the requirement" do
          expect(prepared_manifest_file.content).to eq(manifest.content)
        end
      end

      context "with unlock_requirement set to true" do
        let(:unlock_requirement) { true }

        it "updates the requirement" do
          expect(prepared_manifest_file.content).
            to include('regex = ">= 0.1.41"')
        end

        context "with a git requirement" do
          let(:manifest_fixture_name) { "git_dependency" }
          let(:lockfile_fixture_name) { "git_dependency" }
          let(:dependency_name) { "utf8-ranges" }
          let(:dependency_version) do
            "83141b376b93484341c68fbca3ca110ae5cd2708"
          end
          let(:string_req) { nil }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/BurntSushi/utf8-ranges",
              branch: nil,
              ref: nil
            }
          end

          it "doesn't update the requirement" do
            expect(prepared_manifest_file.content).
              to include('git = "https://github.com/BurntSushi/utf8-ranges"')
            expect(prepared_manifest_file.content).
              to include('version = ">= 1.0.0"')
          end
        end
      end
    end

    describe "the updated lockfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Cargo.lock" } }
      it { is_expected.to eq(lockfile) }
    end

    context "without a lockfile" do
      let(:dependency_files) { [manifest] }
      its(:length) { is_expected.to eq(1) }
    end
  end
end
