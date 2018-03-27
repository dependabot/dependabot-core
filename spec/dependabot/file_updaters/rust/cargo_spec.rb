# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/rust/cargo"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Rust::Cargo do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(content: manifest_body, name: "Cargo.toml")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Cargo.lock", content: lockfile_body)
  end
  let(:manifest_body) { fixture("rust", "manifests", manifest_fixture_name) }
  let(:lockfile_body) { fixture("rust", "lockfiles", lockfile_fixture_name) }
  let(:manifest_fixture_name) { "exact_version_specified" }
  let(:lockfile_fixture_name) { "exact_version_specified" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "time",
      version: "0.1.39",
      requirements: [
        { file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }
      ],
      previous_version: "0.1.38",
      previous_requirements: [
        { file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }
      ],
      package_manager: "cargo"
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "Cargo.lock" }.content
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).
          to include(%(name = "time"\nversion = "0.1.39"))
        expect(updated_lockfile_content).to include(
          "a15375f1df02096fb3317256ce2cee6a1f42fc84ea5ad5fc8c421cfe40c73098"
        )
        expect(updated_lockfile_content).to_not include(
          "d5d788d3aa77bc0ef3e9621256885555368b47bd495c13dd2e7413c89f845520"
        )
      end
    end
  end
end
