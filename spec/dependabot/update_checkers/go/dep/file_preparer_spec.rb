# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/go/dep/file_preparer"

RSpec.describe Dependabot::UpdateCheckers::Go::Dep::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      unlock_requirement: unlock_requirement,
      remove_git_source: remove_git_source,
      replacement_git_pin: replacement_git_pin,
      latest_allowable_version: latest_allowable_version
    )
  end

  let(:dependency_files) { [manifest, lockfile] }
  let(:unlock_requirement) { true }
  let(:remove_git_source) { false }
  let(:replacement_git_pin) { nil }
  let(:latest_allowable_version) { nil }

  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.toml",
      content: fixture("go", "gopkg_tomls", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.lock",
      content: fixture("go", "gopkg_locks", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "bare_version.toml" }
  let(:lockfile_fixture_name) { "bare_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "dep"
    )
  end
  let(:requirements) do
    [{
      file: "Gopkg.toml",
      requirement: string_req,
      groups: [],
      source: source
    }]
  end
  let(:dependency_name) { "github.com/dgrijalva/jwt-go" }
  let(:source) { { type: "default", source: "github.com/dgrijalva/jwt-go" } }
  let(:dependency_version) { "1.0.1" }
  let(:string_req) { "1.0.0" }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    its(:length) { is_expected.to eq(2) }

    describe "the updated Gopkg.toml" do
      subject(:prepared_manifest_file) do
        prepared_dependency_files.find { |f| f.name == "Gopkg.toml" }
      end

      context "with unlock_requirement set to false" do
        let(:unlock_requirement) { false }

        it "doesn't update the requirement" do
          expect(prepared_manifest_file.content).to include('version = "1.0.0"')
        end
      end

      context "with unlock_requirement set to true" do
        let(:unlock_requirement) { true }

        it "updates the requirement" do
          expect(prepared_manifest_file.content).
            to include('version = ">= 1.0.1"')
        end

        context "without a lockfile" do
          let(:dependency_files) { [manifest] }
          let(:dependency_version) { nil }
          let(:string_req) { "1.0.0" }

          it "updates the requirement" do
            expect(prepared_manifest_file.content).
              to include('version = ">= 1.0.0"')
          end
        end

        context "with a blank requirement" do
          let(:manifest_fixture_name) { "no_version.toml" }
          let(:lockfile_fixture_name) { "no_version.lock" }
          let(:string_req) { nil }

          it "updates the requirement" do
            expect(prepared_manifest_file.content).
              to include('version = ">= 1.0.1"')
          end

          context "and a latest_allowable_version" do
            let(:latest_allowable_version) { Gem::Version.new("1.6.0") }

            it "updates the requirement" do
              expect(prepared_manifest_file.content).
                to include('version = ">= 1.0.1, <= 1.6.0"')
            end

            context "that is lower than the current lower bound" do
              let(:latest_allowable_version) { Gem::Version.new("0.1.0") }

              it "updates the requirement" do
                expect(prepared_manifest_file.content).
                  to include('version = ">= 1.0.1"')
              end
            end
          end

          context "without a lockfile" do
            let(:dependency_files) { [manifest] }
            let(:dependency_version) { nil }
            let(:string_req) { nil }

            it "updates the requirement" do
              expect(prepared_manifest_file.content).
                to include('version = ">= 0"')
            end
          end
        end

        context "with a git requirement" do
          context "with a branch" do
            let(:manifest_fixture_name) { "branch.toml" }
            let(:lockfile_fixture_name) { "branch.lock" }
            let(:dependency_name) { "golang.org/x/text" }
            let(:dependency_version) do
              "7dd2c8130f5e924233f5543598300651c386d431"
            end
            let(:string_req) { nil }
            let(:source) do
              {
                type: "git",
                url: "https://github.com/golang/text",
                branch: "master",
                ref: nil
              }
            end

            it "doesn't update the manifest" do
              expect(prepared_manifest_file.content).
                to_not include("version =")
            end

            context "that we want to remove" do
              let(:remove_git_source) { true }

              it "removes the git source" do
                expect(prepared_manifest_file.content).
                  to include('version = ">= 0"')
                expect(prepared_manifest_file.content).
                  to_not include("branch = ")
              end
            end
          end

          context "with a tag" do
            let(:manifest_fixture_name) { "tag_as_revision.toml" }
            let(:lockfile_fixture_name) { "tag_as_revision.lock" }
            let(:dependency_version) { "v0.2.0" }
            let(:dependency_name) { "golang.org/x/text" }
            let(:string_req) { nil }
            let(:source) do
              {
                type: "git",
                url: "https://github.com/golang/text",
                branch: nil,
                ref: "v0.2.0"
              }
            end

            context "without a replacement tag" do
              let(:replacement_git_pin) { nil }

              it "doesn't update the tag" do
                expect(prepared_manifest_file.content).
                  to include('revision = "v0.2.0"')
                expect(prepared_manifest_file.content).
                  to_not include("version =")
              end

              context "when we want to remove the tag" do
                let(:remove_git_source) { true }

                it "removes the git source" do
                  expect(prepared_manifest_file.content).
                    to include('version = ">= 0"')
                  expect(prepared_manifest_file.content).
                    to_not include("revision = ")
                end
              end
            end

            context "with a replacement tag" do
              let(:replacement_git_pin) { "v1.0.0" }

              it "updates the requirement" do
                expect(prepared_manifest_file.content).
                  to include('revision = "v1.0.0"')
                expect(prepared_manifest_file.content).
                  to_not include("version =")
              end
            end
          end
        end
      end
    end

    describe "the updated lockfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Gopkg.lock" } }
      it { is_expected.to eq(lockfile) }
    end

    context "without a lockfile" do
      let(:dependency_files) { [manifest] }
      its(:length) { is_expected.to eq(1) }
    end
  end
end
