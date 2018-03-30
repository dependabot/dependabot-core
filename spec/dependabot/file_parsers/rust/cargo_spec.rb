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
