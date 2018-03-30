# frozen_string_literal: true

require "dependabot/file_parsers/rust/cargo"
require "dependabot/dependency_file"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Rust::Cargo do
  it_behaves_like "a dependency file parser"

  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Cargo.toml",
      content: fixture("rust", "manifests", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Cargo.lock",
      content: fixture("rust", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "exact_version_specified" }
  let(:lockfile_fixture_name) { "exact_version_specified" }

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

      context "with a path dependency" do
        let(:manifest_fixture_name) { "path_dependency" }
        let(:lockfile_fixture_name) { "path_dependency" }
        let(:files) { [manifest, lockfile, path_dependency_manifest] }
        let(:path_dependency_manifest) do
          Dependabot::DependencyFile.new(
            name: "src/s3/Cargo.toml",
            content: fixture("rust", "manifests", "cargo-registry-s3")
          )
        end

        its(:length) { is_expected.to eq(37) }

        describe "top level dependencies" do
          subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

          its(:length) { is_expected.to eq(6) }

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
              expect(dependency.name).to eq("base64")
              expect(dependency.version).to eq("0.9.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "0.9",
                  file: "src/s3/Cargo.toml",
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
            content: fixture("rust", "manifests", "workspace_child")
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
              name: "lib/sub_crate/Cargo.toml",
              content: fixture("rust", "manifests", "workspace_child")
            )
          end
          let(:workspace_child2) do
            Dependabot::DependencyFile.new(
              name: "lib/sub_crate2/Cargo.toml",
              content: workspace_child2_body
            )
          end
          let(:workspace_child3) do
            Dependabot::DependencyFile.new(
              name: "lib/sub_crate3/Cargo.toml",
              content: workspace_child2_body
            )
          end
          let(:workspace_child2_body) do
            fixture("rust", "manifests", "workspace_child_with_path_dependency")
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
                    file: "lib/sub_crate/Cargo.toml",
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
                      file: "lib/sub_crate2/Cargo.toml",
                      groups: ["dependencies"],
                      source: { type: "path" }
                    },
                    {
                      requirement: nil,
                      file: "lib/sub_crate3/Cargo.toml",
                      groups: ["dependencies"],
                      source: { type: "path" }
                    }
                  ]
                )
              end
            end
          end
        end

        context "regression spec: conduit" do
          let(:manifest_fixture_name) { "conduit" }
          let(:lockfile_fixture_name) { "conduit" }
          let(:files) do
            [
              manifest,
              lockfile,
              conduit_proxy,
              conduit_proxy_controller_grpc,
              conduit_proxy_convert,
              conduit_proxy_futures_mpsc_lossy,
              conduit_proxy_router
            ]
          end
          let(:conduit_proxy) do
            Dependabot::DependencyFile.new(
              name: "proxy/Cargo.toml",
              content: fixture("rust", "manifests", "conduit-proxy")
            )
          end
          let(:conduit_proxy_controller_grpc) do
            Dependabot::DependencyFile.new(
              name: "proxy/controller-grpc/Cargo.toml",
              content:
                fixture("rust", "manifests", "conduit-proxy-controller-grpc")
            )
          end
          let(:conduit_proxy_convert) do
            Dependabot::DependencyFile.new(
              name: "proxy/convert/Cargo.toml",
              content: fixture("rust", "manifests", "conduit-proxy-convert")
            )
          end
          let(:conduit_proxy_router) do
            Dependabot::DependencyFile.new(
              name: "proxy/router/Cargo.toml",
              content: fixture("rust", "manifests", "conduit-proxy-router")
            )
          end
          let(:conduit_proxy_futures_mpsc_lossy) do
            Dependabot::DependencyFile.new(
              name: "proxy/futures-mpsc-lossy/Cargo.toml",
              content:
                fixture("rust", "manifests", "conduit-proxy-futures-mpsc-lossy")
            )
          end

          describe "top level dependencies" do
            subject(:top_level_dependencies) do
              dependencies.select(&:top_level?)
            end

            its(:length) { is_expected.to eq(36) }

            describe "a dependency" do
              subject(:dependency) do
                top_level_dependencies.find { |d| d.name == "tokio-core" }
              end

              it "has the right details" do
                expect(dependency).to be_a(Dependabot::Dependency)
                expect(dependency.name).to eq("tokio-core")
                expect(dependency.version).to eq("0.1.12")
                expect(dependency.requirements).to eq(
                  [{
                    requirement: "0.1",
                    file: "proxy/Cargo.toml",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end
          end
        end
      end

      context "with a git dependency" do
        let(:manifest_fixture_name) { "git_dependency" }

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
                  ref: nil
                }
              }]
            )
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

      context "that is unparseable" do
        let(:manifest_fixture_name) { "unparseable" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("Cargo.toml")
            end
        end
      end
    end

    context "with a lockfile" do
      # TODO: This would be 14 if we weren't combining two winapi versions
      its(:length) { is_expected.to eq(13) }

      it "excludes the source application / library" do
        expect(dependencies.map(&:name)).to_not include("dependabot")
      end

      describe "top level dependencies" do
        subject(:top_level_dependencies) { dependencies.select(&:top_level?) }
        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

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
              # Surprisingly, Rust's treats bare requirements as semver reqs
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

        context "with a git dependency" do
          let(:manifest_fixture_name) { "git_dependency_with_tag" }
          let(:lockfile_fixture_name) { "git_dependency_with_tag" }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { dependencies.first }

            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("utf8-ranges")
              expect(dependency.version).
                to eq("d5094c7e9456f2965dec20de671094a98c6929c2")
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

      context "with no dependencies" do
        let(:manifest_fixture_name) { "no_dependencies" }
        let(:lockfile_fixture_name) { "no_dependencies" }
        it { is_expected.to eq([]) }
      end

      context "that is unparseable" do
        let(:lockfile_fixture_name) { "unparseable" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("Cargo.lock")
            end
        end
      end
    end
  end
end
