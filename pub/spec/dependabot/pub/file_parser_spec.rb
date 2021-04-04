# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/pub/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Pub::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [pubspec_yaml_file, pubspec_lock_file] }
  let(:pubspec_yaml_file) do
    Dependabot::DependencyFile.new(name: "pubspec.yaml", content: pubspec_yaml_body)
  end
  let(:pubspec_lock_file) do
    Dependabot::DependencyFile.new(name: "pubspec.lock", content: pubspec_lock_body)
  end
  let(:pubspec_yaml_body) do
    fixture("pubspec_yamlfiles", pubspec_fixture_name + ".yaml")
  end
  let(:pubspec_lock_body) do
    fixture("pubspec_lockfiles", pubspec_fixture_name + ".lock")
  end
  let(:pubspec_fixture_name) { "hosted" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with hosted sources" do
      let(:pubspec_fixture_name) { "hosted" }

      its(:length) { is_expected.to eq(2) }

      # context "that are invalid" do
      #   let(:pubspec_fixture_name) { "invalid_registry.tf" }

      #   it "raises a helpful error" do
      #     expect { parser.parse }.
      #       to raise_error(Dependabot::DependencyFileNotEvaluatable) do |err|
      #         expect(err.message).
      #           to eq("Invalid registry source specified: 'consul/aws'")
      #       end
      #   end
      # end

      # context "that can't be parsed" do
      #   let(:pubspec_fixture_name) { "unparseable.tf" }

      #   it "raises a helpful error" do
      #     expect { parser.parse }.
      #       to raise_error(Dependabot::DependencyFileNotParseable) do |err|
      #         expect(err.file_path).to eq("/main.tf")
      #         expect(err.message).to eq(
      #           "unable to parse HCL: object expected closing RBRACE got: EOF"
      #         )
      #       end
      #   end
      # end

      describe "the first dependency (direct main with caret version)" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "^1.7.0",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dartlang.org"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("path")
          expect(dependency.version).to eq("1.7.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (direct dev with caret version)" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "^1.9.0",
            groups: ["dev_dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dartlang.org"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("pedantic")
          expect(dependency.version).to eq("1.9.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with git sources via ssh" do
      let(:pubspec_fixture_name) { "git_ssh" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency (direct main)" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "git@github.com:dart-lang/path.git",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "git",
              url: "git@github.com:dart-lang/path.git",
              ref: "HEAD",
              resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b",
              branch: nil,
              path: "."
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("path")
          expect(dependency.version).to eq("1.7.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (direct dev)" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "git@github.com:google/pedantic.git",
            groups: ["dev_dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "git",
              url: "git@github.com:google/pedantic.git",
              ref: "HEAD",
              resolved_ref: "2574dd14cabfe718a3bd4ef6651a9d6455e29fcb",
              branch: nil,
              path: "."
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("pedantic")
          expect(dependency.version).to eq("1.9.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      context "with path" do
        let(:pubspec_fixture_name) { "git_ssh_with_path" }

        its(:length) { is_expected.to eq(34) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:rrousselGit/river_pod.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:rrousselGit/river_pod.git",
                ref: "HEAD",
                resolved_ref: "843adaa56bc34d617b07b14bdf4570afb907ee77",
                branch: nil,
                path: "packages/riverpod"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("riverpod")
            expect(dependency.version).to eq("0.13.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:rrousselGit/freezed.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:rrousselGit/freezed.git",
                ref: "HEAD",
                resolved_ref: "cd29a64c3369bff6ccbe794c323b995adf15ac6a",
                branch: nil,
                path: "packages/freezed"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("freezed")
            expect(dependency.version).to eq("0.14.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end

      context "with ref" do
        let(:pubspec_fixture_name) { "git_ssh_with_ref" }

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:dart-lang/path.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:dart-lang/path.git",
                ref: "1.7.0",
                resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b",
                branch: nil,
                path: "."
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("path")
            expect(dependency.version).to eq("1.7.0")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:google/pedantic.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:google/pedantic.git",
                ref: "v1.9.1",
                resolved_ref: "d7fe6f0ca73a10542f3d7abed1818dd0a0693dd4",
                branch: nil,
                path: "."
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("pedantic")
            expect(dependency.version).to eq("1.9.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end

      context "with path and ref" do
        let(:pubspec_fixture_name) { "git_ssh_with_path_and_ref" }

        its(:length) { is_expected.to eq(34) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:rrousselGit/river_pod.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:rrousselGit/river_pod.git",
                ref: "v0.12.4",
                resolved_ref: "97e31d3481b68e4293408b4eef99dc7916dc8147",
                branch: nil,
                path: "packages/riverpod"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("riverpod")
            expect(dependency.version).to eq("0.12.4")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "git@github.com:rrousselGit/freezed.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "git@github.com:rrousselGit/freezed.git",
                ref: "v0.12.7",
                resolved_ref: "2fe149026c3edf4735641255923157fded532b0b",
                branch: nil,
                path: "packages/freezed"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("freezed")
            expect(dependency.version).to eq("0.12.7")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end
    end

    context "with git sources via https" do
      let(:pubspec_fixture_name) { "git_https" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency (direct main)" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "https://github.com/dart-lang/path.git",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "git",
              url: "https://github.com/dart-lang/path.git",
              ref: "HEAD",
              resolved_ref: "49a015d612541e549cfbe657ef48145ca32a98f8",
              branch: nil,
              path: "."
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("path")
          expect(dependency.version).to eq("1.8.1-dev")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (direct dev)" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "https://github.com/google/pedantic.git",
            groups: ["dev_dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "git",
              url: "https://github.com/google/pedantic.git",
              ref: "HEAD",
              resolved_ref: "66f2f6c27581c7936482e83be80b27be2719901c",
              branch: nil,
              path: "."
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("pedantic")
          expect(dependency.version).to eq("1.11.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      context "with path" do
        let(:pubspec_fixture_name) { "git_https_with_path" }

        its(:length) { is_expected.to eq(34) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/rrousselGit/river_pod.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/rrousselGit/river_pod.git",
                ref: "HEAD",
                resolved_ref: "843adaa56bc34d617b07b14bdf4570afb907ee77",
                branch: nil,
                path: "packages/riverpod"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("riverpod")
            expect(dependency.version).to eq("0.13.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/rrousselGit/freezed.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/rrousselGit/freezed.git",
                ref: "HEAD",
                resolved_ref: "cd29a64c3369bff6ccbe794c323b995adf15ac6a",
                branch: nil,
                path: "packages/freezed"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("freezed")
            expect(dependency.version).to eq("0.14.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end

      context "with ref" do
        let(:pubspec_fixture_name) { "git_https_with_ref" }

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/dart-lang/path.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/dart-lang/path.git",
                ref: "1.7.0",
                resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b",
                branch: nil,
                path: "."
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("path")
            expect(dependency.version).to eq("1.7.0")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/google/pedantic.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/google/pedantic.git",
                ref: "v1.9.1",
                resolved_ref: "d7fe6f0ca73a10542f3d7abed1818dd0a0693dd4",
                branch: nil,
                path: "."
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("pedantic")
            expect(dependency.version).to eq("1.9.1")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end

      context "with path and ref" do
        let(:pubspec_fixture_name) { "git_https_with_path_and_ref" }

        its(:length) { is_expected.to eq(34) }

        describe "the first dependency (direct main)" do
          subject(:dependency) { dependencies.first }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/rrousselGit/river_pod.git",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/rrousselGit/river_pod.git",
                ref: "v0.12.4",
                resolved_ref: "97e31d3481b68e4293408b4eef99dc7916dc8147",
                branch: nil,
                path: "packages/riverpod"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("riverpod")
            expect(dependency.version).to eq("0.12.4")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the second dependency (direct dev)" do
          subject(:dependency) { dependencies[1] }
          let(:expected_requirements) do
            [{
              requirement: "https://github.com/rrousselGit/freezed.git",
              groups: ["dev_dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "git",
                url: "https://github.com/rrousselGit/freezed.git",
                ref: "v0.12.7",
                resolved_ref: "2fe149026c3edf4735641255923157fded532b0b",
                branch: nil,
                path: "packages/freezed"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("freezed")
            expect(dependency.version).to eq("0.12.7")
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end
      end
    end
  end
end
