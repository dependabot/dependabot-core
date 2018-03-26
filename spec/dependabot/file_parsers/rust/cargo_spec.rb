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
      # TODO: This would be 16 if we weren't combining two winapi versions
      its(:length) { is_expected.to eq(15) }

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
            expect(dependency.version).to eq("0.1.39")
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
