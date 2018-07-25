# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/go/dep"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Go::Dep do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Gopkg.toml", content: manifest_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Gopkg.lock", content: lockfile_body)
  end
  let(:manifest_body) { fixture("go", "gopkg_tomls", manifest_fixture_name) }
  let(:lockfile_body) { fixture("go", "gopkg_locks", lockfile_fixture_name) }
  let(:manifest_fixture_name) { "bare_version.toml" }
  let(:lockfile_fixture_name) { "bare_version.lock" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "dep"
    )
  end
  let(:dependency_name) { "github.com/dgrijalva/jwt-go" }
  let(:dependency_version) { "3.2.0" }
  let(:dependency_previous_version) { "1.0.1" }
  let(:requirements) { previous_requirements }
  let(:previous_requirements) do
    [{
      file: "Gopkg.toml",
      requirement: "1.0.0",
      groups: [],
      source: {
        type: "default",
        source: "github.com/dgrijalva/jwt-go"
      }
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently, and returns DependencyFiles" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.to_not output.to_stdout }

    context "without a lockfile" do
      let(:files) { [manifest] }

      context "if no files have changed" do
        it "raises a helpful error" do
          expect { updater.updated_dependency_files }.
            to raise_error("No files changed!")
        end
      end

      context "when the requirement in the manifest has changed" do
        let(:requirements) do
          [{
            file: "Gopkg.toml",
            requirement: ">= 1.0.0, < 4.0.0",
            groups: [],
            source: {
              type: "default",
              source: "github.com/dgrijalva/jwt-go"
            }
          }]
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated manifest" do
          subject(:updated_manifest_content) do
            updated_files.find { |f| f.name == "Gopkg.toml" }.content
          end

          it "includes the new requirement" do
            expect(described_class::ManifestUpdater).
              to receive(:new).
              with(dependencies: [dependency], manifest: manifest).
              and_call_original

            expect(updated_manifest_content).
              to include(%(version = ">= 1.0.0, < 4.0.0"))
          end
        end
      end
    end
  end
end
