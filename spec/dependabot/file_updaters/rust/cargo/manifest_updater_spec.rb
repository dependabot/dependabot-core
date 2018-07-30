# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/rust/cargo/manifest_updater"

RSpec.describe Dependabot::FileUpdaters::Rust::Cargo::ManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest: manifest,
      dependencies: [dependency]
    )
  end

  let(:manifest) do
    Dependabot::DependencyFile.new(name: "Cargo.toml", content: manifest_body)
  end
  let(:manifest_body) { fixture("rust", "manifests", manifest_fixture_name) }
  let(:manifest_fixture_name) { "bare_version_specified" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_version: dependency_previous_version,
      previous_requirements: previous_requirements,
      package_manager: "cargo"
    )
  end
  let(:dependency_name) { "time" }
  let(:dependency_version) { "0.1.40" }
  let(:dependency_previous_version) { "0.1.38" }
  let(:requirements) { previous_requirements }
  let(:previous_requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end

  describe "#updated_manifest_content" do
    subject(:updated_manifest_content) { updater.updated_manifest_content }

    context "if no files have changed" do
      it { is_expected.to eq(manifest.content) }
    end

    context "when the requirement has changed" do
      let(:requirements) do
        [{
          file: "Cargo.toml",
          requirement: "0.1.38",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to include(%(time = "0.1.38")) }
      it { is_expected.to include(%(regex = "0.1.41")) }
      it { is_expected.to_not include(%("time" = "0.1.12")) }

      context "with an optional dependency" do
        let(:manifest_fixture_name) { "optional_dependency" }
        let(:dependency_name) { "utf8-ranges" }
        let(:dependency_version) { "1.0.0" }
        let(:dependency_previous_version) { "0.1.3" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: "1.0.0",
            groups: [],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: "0.1.3",
            groups: [],
            source: nil
          }]
        end

        it "includes the new requirement" do
          expect(updated_manifest_content).to include(
            %(utf8-ranges = { version = "1.0.0", optional = true })
          )
        end
      end

      context "with a repeated dependency when only one req has changed" do
        let(:manifest_fixture_name) { "repeated_dependency" }
        let(:requirements) do
          [
            {
              file: "Cargo.toml",
              requirement: "0.1.38",
              groups: ["dependencies"],
              source: nil
            },
            {
              file: "Cargo.toml",
              requirement: "0.1.13",
              groups: ["build-dependencies"],
              source: nil
            }
          ]
        end
        let(:previous_requirements) do
          [
            {
              file: "Cargo.toml",
              requirement: "0.1.12",
              groups: ["dependencies"],
              source: nil
            },
            {
              file: "Cargo.toml",
              requirement: "0.1.13",
              groups: ["build-dependencies"],
              source: nil
            }
          ]
        end

        it { is_expected.to include(%(version = "0.1.38")) }
        it { is_expected.to include(%(time = "0.1.13")) }
      end

      context "with a git dependency" do
        context "with an updated tag" do
          let(:manifest_fixture_name) { "git_dependency_with_tag" }
          let(:dependency_name) { "utf8-ranges" }
          let(:dependency_version) do
            "83141b376b93484341c68fbca3ca110ae5cd2708"
          end
          let(:dependency_previous_version) do
            "d5094c7e9456f2965dec20de671094a98c6929c2"
          end
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: nil,
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: "1.0.0"
              }
            }]
          end
          let(:previous_requirements) do
            [{
              file: "Cargo.toml",
              requirement: nil,
              groups: ["dependencies"],
              source: {
                type: "git",
                url: "https://github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: "0.1.3"
              }
            }]
          end

          it { is_expected.to include(', tag = "1.0.0" }') }
        end
      end

      context "with a feature dependency" do
        let(:manifest_fixture_name) { "feature_dependency" }
        let(:dependency_name) { "gtk" }
        let(:dependency_version) { "0.4.0" }
        let(:dependency_previous_version) { "0.3.0" }
        let(:requirements) do
          [{
            file: "Cargo.toml",
            requirement: "0.4.0",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Cargo.toml",
            requirement: "0.3.0",
            groups: ["dependencies"],
            source: nil
          }]
        end

        context "that is a build dependency" do
          let(:manifest_fixture_name) { "feature_build_dependency" }
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: "0.4.0",
              groups: ["build-dependencies"],
              source: nil
            }]
          end
          let(:previous_requirements) do
            [{
              file: "Cargo.toml",
              requirement: "0.3.0",
              groups: ["build-dependencies"],
              source: nil
            }]
          end

          it "includes the new requirement" do
            expect(updated_manifest_content).
              to include(
                %([build-dependencies.gtk]\nversion = "0.4.0"\nfeatures)
              )
          end
        end

        it "includes the new requirement" do
          expect(updated_manifest_content).
            to include(%([dependencies.gtk]\nversion = "0.4.0"\nfeatures))
        end
      end
    end
  end
end
