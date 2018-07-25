# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/go/dep/lockfile_updater"

RSpec.describe Dependabot::FileUpdaters::Go::Dep::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: dependency_files,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:dependency_files) { [manifest, lockfile] }
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

  describe "#updated_lockfile_content" do
    subject(:updated_lockfile_content) { updater.updated_lockfile_content }

    context "with a released version" do
      context "if no files have changed" do
        let(:dependency_version) { "1.0.1" }
        let(:dependency_previous_version) { "1.0.1" }

        # Ideally this would spec that the lockfile didn't change at all. That
        # isn't the case because the inputs-hash changes (whilst on dep 0.4.1)
        it "doesn't update the version in the lockfile" do
          expect(updated_lockfile_content).to include(%(version = "v1.0.1"))
          expect(updated_lockfile_content).
            to include("fbcb3e4b637bdc5ef2257eb2d0fe1d914a499386")
        end
      end

      context "when the version has changed but the requirement hasn't" do
        let(:dependency_version) { "1.0.2" }
        let(:dependency_previous_version) { "1.0.1" }

        it "updates the lockfile correctly" do
          expect(updated_lockfile_content).to include(%(version = "v1.0.2"))
          expect(updated_lockfile_content).
            to include("0987fb8fd48e32823701acdac19f5cfe47339de4")
        end
      end
    end

    context "with a git dependency" do
      context "updating to the tip of a branch" do
        let(:manifest_fixture_name) { "branch.toml" }
        let(:lockfile_fixture_name) { "branch.lock" }

        let(:dependency_name) { "golang.org/x/text" }
        let(:dependency_version) { "0605a8320aceb4207a5fb3521281e17ec2075476" }
        let(:dependency_previous_version) do
          "7dd2c8130f5e924233f5543598300651c386d431"
        end
        let(:requirements) { previous_requirements }
        let(:previous_requirements) do
          [{
            file: "Gopkg.toml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/golang/text",
              branch: "master",
              ref: nil
            }
          }]
        end

        it "updates the lockfile correctly" do
          expect(updated_lockfile_content).
            to include("0605a8320aceb4207a5fb3521281e17ec2075476")
          expect(updated_lockfile_content).
            to include(%(branch = "master"\n  name = "golang.org/x/text"))
        end

        context "to use a release instead" do
          let(:dependency_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "Gopkg.toml",
              requirement: "^0.3.0",
              groups: [],
              source: {
                type: "default",
                source: "golang.org/x/text"
              }
            }]
          end

          it "updates the lockfile correctly" do
            expect(updated_lockfile_content).
              to include(%(version = "v0.3.0"))
            expect(updated_lockfile_content).
              to include(%(vision = "f21a4dfb5e38f5895301dc265a8def02365cc3d0"))
          end
        end
      end

      context "updating a reference" do
        let(:manifest_fixture_name) { "tag_as_revision.toml" }
        let(:lockfile_fixture_name) { "tag_as_revision.lock" }

        let(:dependency_name) { "golang.org/x/text" }
        let(:dependency_version) { "v0.3.0" }
        let(:dependency_previous_version) { "v0.2.0" }
        let(:requirements) do
          [{
            file: "Gopkg.toml",
            requirement: nil,
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
            file: "Gopkg.toml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/golang/text",
              branch: nil,
              ref: "v0.2.0"
            }
          }]
        end

        it "updates the lockfile correctly" do
          expect(updated_lockfile_content).to include(%(revision = "v0.3.0"))
        end

        context "to use a release instead" do
          let(:dependency_version) { "0.3.0" }
          let(:requirements) do
            [{
              file: "Gopkg.toml",
              requirement: "^0.3.0",
              groups: [],
              source: {
                type: "default",
                source: "golang.org/x/text"
              }
            }]
          end

          it "updates the lockfile correctly" do
            expect(updated_lockfile_content).
              to include(%(version = "v0.3.0"))
            expect(updated_lockfile_content).
              to include(%(vision = "f21a4dfb5e38f5895301dc265a8def02365cc3d0"))
          end
        end
      end
    end
  end
end
