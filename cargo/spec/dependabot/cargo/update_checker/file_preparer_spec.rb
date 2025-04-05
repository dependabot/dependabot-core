# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/cargo/update_checker/file_preparer"

RSpec.describe Dependabot::Cargo::UpdateChecker::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      unlock_requirement: unlock_requirement,
      replacement_git_pin: replacement_git_pin,
      latest_allowable_version: latest_allowable_version
    )
  end

  let(:dependency_files) { [manifest, lockfile] }
  let(:unlock_requirement) { true }
  let(:replacement_git_pin) { nil }
  let(:latest_allowable_version) { nil }

  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("manifests", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
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
          expect(prepared_manifest_file.content).to include('regex = "0.1.41"')
        end
      end

      context "with unlock_requirement set to true" do
        let(:unlock_requirement) { true }

        it "updates the requirement" do
          expect(prepared_manifest_file.content)
            .to include('regex = ">= 0.1.41"')
        end

        context "when dealing with a target-specific dependency" do
          let(:manifest_fixture_name) { "target_dependency" }
          let(:lockfile_fixture_name) { "target_dependency" }
          let(:dependency_name) { "time" }
          let(:dependency_version) { "0.1.12" }
          let(:string_req) { "<= 0.1.12" }

          it "updates the requirement" do
            expect(prepared_manifest_file.content)
              .to include('time = ">= 0.1.12"')
            expect(prepared_manifest_file.content)
              .not_to include('time = "<= 0.1.12"')
          end
        end

        context "without a lockfile" do
          let(:dependency_files) { [manifest] }
          let(:dependency_version) { nil }
          let(:string_req) { "0.1" }

          it "updates the requirement" do
            expect(prepared_manifest_file.content)
              .to include('regex = ">= 0.1"')
          end

          context "when the dependency is specified as an alias" do
            let(:manifest_fixture_name) { "alias" }
            let(:dependency_name) { "time" }
            let(:string_req) { "0.1.12" }

            it "updates the requirement" do
              expect(prepared_manifest_file.content)
                .to include(
                  "[dependencies.alias]\n" \
                  "package = \"time\"\n" \
                  "version = \">= 0.1.12\""
                )
            end
          end

          context "when another dependency is aliased to the same name" do
            let(:manifest_fixture_name) { "alias" }
            let(:dependency_name) { "alias" }
            let(:string_req) { "0.1.12" }

            it "doesn't update the requirement" do
              expect(prepared_manifest_file.content)
                .to include(
                  "[dependencies.alias]\n" \
                  "package = \"time\"\n" \
                  "version = \"0.1.12\""
                )
            end
          end
        end

        context "with a support file (e.g., a path dependency manifest)" do
          before { manifest.support_file = true }

          let(:dependency_version) { nil }

          it "does not update the requirement" do
            expect(prepared_manifest_file.content)
              .to include('regex = "0.1.41"')
          end
        end

        context "with a blank requirement" do
          let(:manifest_fixture_name) { "blank_version" }
          let(:lockfile_fixture_name) { "blank_version" }
          let(:string_req) { nil }

          it "updates the requirement" do
            expect(prepared_manifest_file.content)
              .to include('regex = ">= 0.1.41"')
          end

          context "when a latest_allowable_version is present" do
            let(:latest_allowable_version) { Gem::Version.new("1.6.0") }

            it "updates the requirement" do
              expect(prepared_manifest_file.content)
                .to include('regex = ">= 0.1.41, <= 1.6.0"')
            end

            context "when the value is lower than the current lower bound" do
              let(:latest_allowable_version) { Gem::Version.new("0.1.0") }

              it "updates the requirement" do
                expect(prepared_manifest_file.content)
                  .to include('regex = ">= 0.1.41"')
              end
            end
          end

          context "without a lockfile" do
            let(:dependency_files) { [manifest] }
            let(:dependency_version) { nil }
            let(:string_req) { nil }

            it "updates the requirement" do
              expect(prepared_manifest_file.content)
                .to include('regex = ">= 0"')
            end

            context "with a pre-release specified" do
              let(:dependency_name) { "nom" }
              let(:manifest_fixture_name) { "prerelease_specified" }
              let(:string_req) { "4.0.0-beta3" }
              let(:latest_allowable_version) { "4.0.0" }

              it "updates the requirement" do
                expect(prepared_manifest_file.content)
                  .to include('nom = ">= 4.0.0-beta3, <= 4.0.0"')
              end
            end
          end
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

          it "updates the requirement" do
            expect(prepared_manifest_file.content)
              .to include('git = "https://github.com/BurntSushi/utf8-ranges"')
            expect(prepared_manifest_file.content)
              .to include('version = ">= 1.0.0"')
          end

          context "when using ssh" do
            let(:manifest_fixture_name) { "git_dependency_ssh" }
            let(:lockfile_fixture_name) { "git_dependency_ssh" }

            let(:source) do
              {
                type: "git",
                url: "ssh://git@github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: nil
              }
            end

            it "sanitizes the requirement" do
              expect(prepared_manifest_file.content)
                .to include('git = "https://github.com/BurntSushi/utf8-ranges"')
            end
          end

          context "with a tag" do
            let(:manifest_fixture_name) { "git_dependency_with_tag" }
            let(:lockfile_fixture_name) { "git_dependency_with_tag" }
            let(:dependency_version) do
              "d5094c7e9456f2965dec20de671094a98c6929c2"
            end
            let(:source) do
              {
                type: "git",
                url: "https://github.com/BurntSushi/utf8-ranges",
                branch: nil,
                ref: "0.1.3"
              }
            end

            context "without a replacement tag" do
              let(:replacement_git_pin) { nil }

              it "updates the requirement but not the tag" do
                expect(prepared_manifest_file.content)
                  .to include('"https://github.com/BurntSushi/utf8-ranges"')
                expect(prepared_manifest_file.content)
                  .to include('version = ">= 0.1.3"')
                expect(prepared_manifest_file.content)
                  .to include('tag = "0.1.3"')
              end
            end

            context "with a replacement tag" do
              let(:replacement_git_pin) { "1.0.0" }

              it "updates the requirement and the tag" do
                expect(prepared_manifest_file.content)
                  .to include('"https://github.com/BurntSushi/utf8-ranges"')
                expect(prepared_manifest_file.content)
                  .to include('version = ">= 0.1.3"')
                expect(prepared_manifest_file.content)
                  .to include('tag = "1.0.0"')
              end
            end
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
