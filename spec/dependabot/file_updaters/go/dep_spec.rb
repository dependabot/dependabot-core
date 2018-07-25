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
            expect(updated_manifest_content).
              to include(%(version = ">= 1.0.0, < 4.0.0"))
          end
        end
      end

      context "when the requirement in the manifest has been deleted" do
        let(:requirements) do
          [{
            file: "Gopkg.toml",
            requirement: nil,
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
            expect(updated_manifest_content).
              to end_with(%(name = "github.com/dgrijalva/jwt-go"\n))
          end
        end
      end

      context "when a requirement is being added to the manifest" do
        let(:manifest_fixture_name) { "no_version.toml" }
        let(:lockfile_fixture_name) { "no_version.lock" }
        let(:previous_requirements) do
          [{
            file: "Gopkg.toml",
            requirement: nil,
            groups: [],
            source: {
              type: "default",
              source: "github.com/dgrijalva/jwt-go"
            }
          }]
        end
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
            expect(updated_manifest_content).
              to end_with("  name = \"github.com/dgrijalva/jwt-go\"\n"\
                          "  version = \">= 1.0.0, < 4.0.0\"\n")
          end
        end
      end

      context "when the tag in the manifest has changed" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }
        let(:dependency_name) { "golang.org/x/text" }
        let(:dependency_version) { "v0.3.0" }
        let(:dependency_previous_version) { "v0.2.0" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "Gopkg.toml",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/golang/text",
              branch: nil,
              ref: "v0.3.0"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: nil,
            file: "Gopkg.toml",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/golang/text",
              branch: nil,
              ref: "v0.2.0"
            }
          }]
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated manifest" do
          subject(:updated_manifest_content) do
            updated_files.find { |f| f.name == "Gopkg.toml" }.content
          end

          it "includes the new tag" do
            expect(updated_manifest_content).to include(%(revision = "v0.3.0"))
          end
        end
      end

      context "when switching from a git revision to a release" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }
        let(:dependency_name) { "golang.org/x/text" }
        let(:dependency_version) { "0.3.0" }
        let(:dependency_previous_version) { "v0.2.0" }
        let(:requirements) do
          [{
            requirement: "^0.3.0",
            file: "Gopkg.toml",
            groups: [],
            source: {
              type: "default",
              source: "golang.org/x/text"
            }
          }]
        end
        let(:previous_requirements) do
          [{
            requirement: nil,
            file: "Gopkg.toml",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/golang/text",
              branch: nil,
              ref: "v0.2.0"
            }
          }]
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated manifest" do
          subject(:updated_manifest_content) do
            updated_files.find { |f| f.name == "Gopkg.toml" }.content
          end

          it "includes the new tag" do
            expect(updated_manifest_content).
              to end_with("  name = \"golang.org/x/text\"\n"\
                          "  version = \"^0.3.0\"\n")
          end
        end
      end
    end
  end
end
