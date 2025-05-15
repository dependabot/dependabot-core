# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/file_parser"
require "dependabot/dependency_file"
require "dependabot/source"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Cargo::FileParser do
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("manifests", manifest_fixture_name)
    )
  end
  let(:files) { [manifest, lockfile] }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with only a manifest" do
      let(:files) { [manifest] }

      its(:length) { is_expected.to eq(2) }

      context "with an exact version specified" do
        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("time")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.12",
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "with no version specified" do
        let(:manifest_fixture_name) { "blank_version" }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("time")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "with a dependency using an alias" do
        let(:manifest_fixture_name) { "alias" }

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("regex")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.41",
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "when the project is part of a workspace but not the root" do
        let(:manifest_fixture_name) { "workspace_child" }

        it "raises a helpful error" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
              expect(error.message)
                .to include("This project is part of a Rust workspace")
            end
        end
      end

      context "with declarations in dependencies and build-dependencies" do
        let(:manifest_fixture_name) { "repeated_dependency" }

        describe "the last dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("time")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [
                {
                  requirement: "0.1.12",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                },
                {
                  requirement: "0.1.13",
                  file: "Cargo.toml",
                  groups: ["build-dependencies"],
                  source: nil
                }
              ]
            )
          end
        end
      end

      context "with a path dependency" do
        let(:manifest_fixture_name) { "path_dependency" }
        let(:lockfile_fixture_name) { "path_dependency" }
        let(:files) { [manifest, lockfile, path_dependency_manifest] }
        let(:path_dependency_manifest) do
          Dependabot::DependencyFile.new(
            name: "src/s3/Cargo.toml",
            content: fixture("manifests", "cargo-registry-s3"),
            support_file: true
          )
        end

        its(:length) { is_expected.to eq(37) }

        describe "top level dependencies" do
          subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("cargo-registry-s3")
              expect(dependency.version).to eq("0.2.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.2.0",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: { type: "path" }
                }]
              )
            end
          end

          describe "the last dependency" do
            subject(:dependency) { top_level_dependencies.last }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("regex")
              expect(dependency.version).to eq("0.1.38")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "=0.1.38",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end

      context "with workspaces" do
        let(:manifest_fixture_name) { "workspace_root" }
        let(:lockfile_fixture_name) { "workspace" }
        let(:files) { [manifest, lockfile, workspace_child] }
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "lib/sub_crate/Cargo.toml",
            content: fixture("manifests", "workspace_child")
          )
        end

        its(:length) { is_expected.to eq(13) }

        describe "top level dependencies" do
          subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("regex")
              expect(dependency.version).to eq("0.2.10")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "=0.2.10",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "the last dependency" do
            subject(:dependency) { top_level_dependencies.last }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("log")
              expect(dependency.version).to eq("0.4.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "=0.4.0",
                  file: "lib/sub_crate/Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with an override (specified as a patch)" do
          subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

          let(:manifest_fixture_name) { "workspace_root_with_patch" }
          let(:lockfile_fixture_name) { "workspace_with_patch" }

          it "excludes the patched dependency" do
            expect(top_level_dependencies.map(&:name)).to eq(["regex"])
          end
        end

        context "with a virtual workspace root" do
          let(:manifest_fixture_name) { "virtual_workspace_root" }
          let(:lockfile_fixture_name) { "virtual_workspace" }
          let(:files) do
            [
              manifest,
              lockfile,
              workspace_child,
              workspace_child2,
              workspace_child3
            ]
          end
          let(:workspace_child) do
            Dependabot::DependencyFile.new(
              name: "src/sub_crate/Cargo.toml",
              content: fixture("manifests", "workspace_child")
            )
          end
          let(:workspace_child2) do
            Dependabot::DependencyFile.new(
              name: "src/sub_crate2/Cargo.toml",
              content: workspace_child2_body
            )
          end
          let(:workspace_child3) do
            Dependabot::DependencyFile.new(
              name: "src/sub_crate3/Cargo.toml",
              content: workspace_child2_body
            )
          end
          let(:workspace_child2_body) do
            fixture("manifests", "workspace_child_with_path_dependency")
          end

          describe "top level dependencies" do
            subject(:top_level_dependencies) do
              dependencies.select(&:top_level?)
            end

            its(:length) { is_expected.to eq(2) }

            describe "the first dependency" do
              subject(:dependency) { top_level_dependencies.first }

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("log")
                expect(dependency.version).to eq("0.4.0")
                expect(dependency.requirements).to eq(
                  [{
                    requirement: "=0.4.0",
                    file: "src/sub_crate/Cargo.toml",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end

            describe "the last dependency" do
              subject(:dependency) { top_level_dependencies.last }

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("dependabot_sub_crate")
                expect(dependency.version).to eq("0.2.0")
                expect(dependency.requirements).to eq(
                  [
                    {
                      requirement: nil,
                      file: "src/sub_crate2/Cargo.toml",
                      groups: ["dependencies"],
                      source: { type: "path" }
                    },
                    {
                      requirement: nil,
                      file: "src/sub_crate3/Cargo.toml",
                      groups: ["dependencies"],
                      source: { type: "path" }
                    }
                  ]
                )
              end
            end
          end

          context "when using an old format lockfile" do
            let(:lockfile_fixture_name) { "virtual_workspace_old_format" }

            its(:length) { is_expected.to eq(2) }
          end
        end
      end

      context "with workspace dependencies" do
        let(:manifest_fixture_name) { "workspace_dependencies_root" }
        let(:lockfile_fixture_name) { "workspace_dependencies" }
        let(:files) do
          [
            manifest,
            lockfile,
            workspace_child
          ]
        end
        let(:workspace_child) do
          Dependabot::DependencyFile.new(
            name: "lib/inherit_ws_dep/Cargo.toml",
            content: fixture("manifests", "workspace_dependencies_child")
          )
        end

        describe "top level dependencies" do
          subject(:top_level_dependencies) do
            dependencies.select(&:top_level?)
          end

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("log")
              expect(dependency.version).to eq("0.4.0")
              expect(dependency.requirements).to eq(
                [
                  {
                    requirement: "=0.4.0",
                    file: "Cargo.toml",
                    groups: ["workspace.dependencies"],
                    source: nil
                  },
                  {
                    requirement: nil,
                    file: "lib/inherit_ws_dep/Cargo.toml",
                    groups: ["dependencies"],
                    source: nil
                  }
                ]
              )
            end
          end
        end
      end

      context "with a git dependency" do
        let(:manifest_fixture_name) { "git_dependency" }

        describe "the last dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("utf8-ranges")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/BurntSushi/utf8-ranges",
                  branch: nil,
                  ref: nil
                }
              }]
            )
          end
        end

        context "with an ssh URL" do
          let(:manifest_fixture_name) { "git_dependency_ssh" }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("utf8-ranges")
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: nil,
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: {
                    type: "git",
                    url: "ssh://git@github.com/BurntSushi/utf8-ranges",
                    branch: nil,
                    ref: nil
                  }
                }]
              )
            end
          end
        end

        context "with a tag" do
          let(:manifest_fixture_name) { "git_dependency_with_tag" }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("utf8-ranges")
              expect(dependency.version).to be_nil
              expect(dependency.requirements).to eq(
                [{
                  requirement: nil,
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/BurntSushi/utf8-ranges",
                    branch: nil,
                    ref: "0.1.3"
                  }
                }]
              )
            end
          end
        end
      end

      context "with an optional dependency" do
        let(:manifest_fixture_name) { "optional_dependency" }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("utf8-ranges")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.3",
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "when the input is unparseable" do
        let(:manifest_fixture_name) { "unparseable" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("Cargo.toml")
            end
        end
      end

      context "when there are value overwrite issues" do
        let(:manifest_fixture_name) { "unparseable_value_overwrite" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("Cargo.toml")
            end
        end
      end
    end

    context "with a lockfile" do
      its(:length) { is_expected.to eq(10) }

      it "excludes the source application / library" do
        expect(dependencies.map(&:name)).not_to include("dependabot")
      end

      describe "top level dependencies" do
        subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject(:dependency) { top_level_dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("time")
            # Surprisingly, Rust's treats bare requirements as semver reqs
            expect(dependency.version).to eq("0.1.38")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.1.12",
                file: "Cargo.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end

        context "with no version specified" do
          let(:manifest_fixture_name) { "blank_version" }
          let(:lockfile_fixture_name) { "blank_version" }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("time")
              expect(dependency.version).to eq("0.1.38")
              expect(dependency.requirements).to eq(
                [{
                  requirement: nil,
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a target-specific dependency" do
          let(:manifest_fixture_name) { "target_dependency" }
          let(:lockfile_fixture_name) { "target_dependency" }

          describe "the last dependency" do
            subject(:dependency) { top_level_dependencies.last }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("time")
              expect(dependency.version).to eq("0.1.12")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "<= 0.1.12",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a build version specified" do
          let(:manifest_fixture_name) { "build_version" }
          let(:lockfile_fixture_name) { "build_version" }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("zstd")
              expect(dependency.version).to eq("0.4.19+zstd.1.3.5")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.4.17+zstd.1.3.3",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with dev dependencies" do
          let(:manifest_fixture_name) { "dev_dependencies" }
          let(:lockfile_fixture_name) { "dev_dependencies" }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("time")
              # Surprisingly, Rust's treats bare requirements as semver reqs
              expect(dependency.version).to eq("0.1.39")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.1.12",
                  file: "Cargo.toml",
                  groups: ["dev-dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with multiple versions available of the dependency" do
          let(:manifest_fixture_name) { "multiple_versions" }
          let(:lockfile_fixture_name) { "multiple_versions" }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("rand")
              # Surprisingly, Rust treats bare requirements as semver reqs
              expect(dependency.version).to eq("0.4.1")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.4",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "with a git version in the lockfile too" do
            let(:lockfile_fixture_name) { "multiple_versions_git" }

            its(:length) { is_expected.to eq(2) }

            describe "the first dependency" do
              subject(:dependency) { top_level_dependencies.first }

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("rand")
                # Surprisingly, Rust treats bare requirements as semver reqs
                expect(dependency.version).to eq("0.4.1")
                expect(dependency.requirements).to eq(
                  [{
                    requirement: "0.4",
                    file: "Cargo.toml",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end
          end
        end

        context "with a git dependency" do
          let(:manifest_fixture_name) { "git_dependency_with_tag" }
          let(:lockfile_fixture_name) { "git_dependency_with_tag" }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("utf8-ranges")
              expect(dependency.version)
                .to eq("d5094c7e9456f2965dec20de671094a98c6929c2")
              expect(dependency.requirements).to eq(
                [{
                  requirement: nil,
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/BurntSushi/utf8-ranges",
                    branch: nil,
                    ref: "0.1.3"
                  }
                }]
              )
            end
          end

          context "with an ssh URL" do
            let(:manifest_fixture_name) { "git_dependency_ssh" }
            let(:lockfile_fixture_name) { "git_dependency_ssh" }

            describe "the first dependency" do
              subject(:dependency) { dependencies.first }

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("utf8-ranges")
                expect(dependency.version)
                  .to eq("83141b376b93484341c68fbca3ca110ae5cd2708")
                expect(dependency.requirements).to eq(
                  [{
                    requirement: nil,
                    file: "Cargo.toml",
                    groups: ["dependencies"],
                    source: {
                      type: "git",
                      url: "ssh://git@github.com/BurntSushi/utf8-ranges",
                      branch: nil,
                      ref: nil
                    }
                  }]
                )
              end
            end
          end
        end

        context "with a feature dependency" do
          let(:manifest_fixture_name) { "feature_dependency" }
          let(:lockfile_fixture_name) { "feature_dependency" }

          describe "the first dependency" do
            subject(:dependency) { dependencies.find(&:top_level?) }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("gtk")
              expect(dependency.version).to eq("0.3.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.3.0",
                  file: "Cargo.toml",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "with no requirement specified" do
            let(:manifest_fixture_name) { "feature_dependency_no_version" }

            describe "the first dependency" do
              subject(:dependency) { dependencies.find(&:top_level?) }

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("gtk")
                expect(dependency.version).to eq("0.3.0")
                expect(dependency.requirements).to eq(
                  [{
                    requirement: nil,
                    file: "Cargo.toml",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end
          end
        end
      end

      context "with resolver version 2" do
        let(:manifest_fixture_name) { "resolver2" }
        let(:lockfile_fixture_name) { "no_dependencies" }

        it { is_expected.to eq([]) }
      end

      context "with no dependencies" do
        let(:manifest_fixture_name) { "no_dependencies" }
        let(:lockfile_fixture_name) { "no_dependencies" }

        it { is_expected.to eq([]) }
      end

      context "when the input is unparseable" do
        let(:lockfile_fixture_name) { "unparseable" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("Cargo.lock")
            end
        end
      end
    end
  end
end
