# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dep/file_updater/lockfile_updater"

RSpec.describe Dependabot::Dep::FileUpdater::LockfileUpdater do
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
  let(:manifest_body) { fixture("gopkg_tomls", manifest_fixture_name) }
  let(:lockfile_body) { fixture("gopkg_locks", lockfile_fixture_name) }
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

      context "when the main.go file imports the dependency itself" do
        let(:dependency_files) { [manifest, lockfile, main] }
        let(:main) do
          Dependabot::DependencyFile.new(name: "main.go", content: main_body)
        end
        let(:main_body) { fixture("go_files", "main.go") }
        let(:manifest_fixture_name) { "tilda.toml" }
        let(:lockfile_fixture_name) { "tilda.lock" }

        let(:dependency_name) { "github.com/jinzhu/gorm" }
        let(:dependency_version) { "1.9.1" }
        let(:dependency_previous_version) { "1.0" }
        let(:requirements) do
          [{
            file: "Gopkg.toml",
            requirement: "~1.9.1",
            groups: [],
            source: { type: "default", source: "github.com/jinzhu/gorm" }
          }]
        end
        let(:previous_requirements) do
          [{
            file: "Gopkg.toml",
            requirement: "~1.0.0",
            groups: [],
            source: { type: "default", source: "github.com/jinzhu/gorm" }
          }]
        end

        it "updates the lockfile correctly" do
          expect(updated_lockfile_content).to include(%(version = "v1.9.1"))
          expect(updated_lockfile_content).
            to include("6ed508ec6a4ecb3531899a69cbc746ccf65a4166")
        end
      end
    end

    context "with a subdependency" do
      let(:previous_requirements) { [] }

      context "if there are no constraints in the manifest at all" do
        let(:manifest_fixture_name) { "no_constraints.toml" }

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
        let(:dependency_version) { "6f44c5a2ea40ee3593d98cdcc905cc1fdaa660e2" }
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
            to include("fe223c5a2583471b2791ca99e716c65b4a76117e")
          expect(updated_lockfile_content).
            to include(
              "  branch = \"master\"\n"\
              "  digest = \"1:c87337d434893edf1d41ca09a6c6c84091a665d0d648344"\
              "0d22a4e1d7ba715eb\"\n"\
              "  name = \"golang.org/x/text\""
            )
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

        context "and it was specified as a version" do
          let(:manifest_fixture_name) { "tag_as_version.toml" }
          let(:lockfile_fixture_name) { "tag_as_version.lock" }

          let(:dependency_name) { "github.com/globalsign/mgo" }
          let(:dependency_version) { "r2018.06.15" }
          let(:dependency_previous_version) { "r2018.04.23" }
          let(:requirements) do
            [{
              requirement: nil,
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/globalsign/mgo",
                branch: nil,
                ref: "r2018.06.15"
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
                ref: "r2018.04.23"
              }
            }]
          end

          it "updates the lockfile correctly" do
            expect(updated_lockfile_content).
              to include(%(version = "r2018.06.15"))
            expect(updated_lockfile_content).
              to include(%(revision = "113d3961e7311))
          end
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

    context "with fsnotify as a direct dependency" do
      let(:manifest_fixture_name) { "fsnotify_dep.toml" }
      let(:lockfile_fixture_name) { "fsnotify_dep.lock" }
      let(:previous_requirements) do
        [{
          file: "Gopkg.toml",
          requirement: "~1.2.0",
          groups: [],
          source: {
            type: "default",
            source: "gopkg.in/fsnotify.v1"
          }
        }]
      end
      let(:dependency_name) { "gopkg.in/fsnotify.v1" }
      let(:dependency_version) { "1.2.0" }
      let(:dependency_previous_version) { "1.2.0" }

      it "updates the lockfile correctly" do
        expect { updated_lockfile_content }.to_not raise_error
      end
    end

    context "with fsnotify as a transitive dependency" do
      let(:manifest_fixture_name) { "fsnotify_trans_dep.toml" }
      let(:lockfile_fixture_name) { "fsnotify_trans_dep.lock" }
      let(:previous_requirements) do
        [{
          file: "Gopkg.toml",
          requirement: "~1.6.0",
          groups: [],
          source: {
            type: "default",
            source: "github.com/onsi/ginkgo"
          }
        }]
      end
      let(:dependency_name) { "github.com/onsi/ginkgo" }
      let(:dependency_version) { "1.7.0" }
      let(:dependency_previous_version) { "1.6.0" }

      it "updates the lockfile correctly" do
        expect { updated_lockfile_content }.to_not raise_error
      end
    end
  end
end
