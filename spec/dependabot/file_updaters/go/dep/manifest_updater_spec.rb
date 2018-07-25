# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/go/dep/manifest_updater"

RSpec.describe Dependabot::FileUpdaters::Go::Dep::ManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest: manifest,
      dependencies: [dependency]
    )
  end

  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Gopkg.toml", content: manifest_body)
  end
  let(:manifest_body) { fixture("go", "gopkg_tomls", manifest_fixture_name) }
  let(:manifest_fixture_name) { "bare_version.toml" }

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

  describe "#updated_manifest_content" do
    subject(:updated_manifest_content) { updater.updated_manifest_content }

    context "if no files have changed" do
      it { is_expected.to eq(manifest.content) }
    end

    context "when the requirement has changed" do
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

      it { is_expected.to include(%(version = ">= 1.0.0, < 4.0.0")) }
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

      it { is_expected.to end_with(%(name = "github.com/dgrijalva/jwt-go"\n)) }
    end

    context "when a requirement is being added" do
      let(:manifest_fixture_name) { "no_version.toml" }
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

      it "includes the new requirement" do
        expect(updated_manifest_content).
          to end_with("  name = \"github.com/dgrijalva/jwt-go\"\n"\
                      "  version = \">= 1.0.0, < 4.0.0\"\n")
      end
    end

    context "when the tag in the manifest has changed" do
      let(:manifest_fixture_name) { "tag_as_revision.toml" }
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

      it "includes the new tag" do
        expect(updated_manifest_content).to include(%(revision = "v0.3.0"))
      end
    end

    context "when switching from a git revision to a release" do
      let(:manifest_fixture_name) { "tag_as_revision.toml" }
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

      it "includes the new tag" do
        expect(updated_manifest_content).
          to end_with("  name = \"golang.org/x/text\"\n"\
                      "  version = \"^0.3.0\"\n")
      end
    end
  end
end
