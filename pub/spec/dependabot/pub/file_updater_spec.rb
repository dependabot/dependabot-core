# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Pub::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [pubspec_yaml, pubspec_lock] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:pubspec_lock) do
    Dependabot::DependencyFile.new(
      name: "pubspec.lock",
      content: pubspec_lock_content
    )
  end
  let(:pubspec_yaml) do
    Dependabot::DependencyFile.new(
      name: "pubspec.yaml",
      content: pubspec_yaml_content
    )
  end
  let(:pubspec_yaml_content) { fixture("pubspec_yamlfiles", pubspec_fixture_name + ".yaml") }
  let(:pubspec_lock_content) { fixture("pubspec_lockfiles", pubspec_fixture_name + ".lock") }
  let(:pubspec_fixture_name) { "git_ssh_with_ref" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "path",
      version: "1.8.0",
      previous_version: "1.7.0",
      requirements: [{
        requirement: "git@github.com:dart-lang/path.git",
        groups: ["dependencies"],
        file: "pubspec.yaml",
        source: {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          path: ".",
          branch: nil,
          ref: "1.8.0",
          resolved_ref: "407ab76187fade41c31e39c745b39661b710106c"
        }
      }],
      previous_requirements: [{
        requirement: "git@github.com:dart-lang/path.git",
        groups: ["dependencies"],
        file: "pubspec.yaml",
        source: {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          path: ".",
          branch: nil,
          ref: "1.7.0",
          resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b"
        }
      }],
      package_manager: "pub"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated file" do
      subject(:updated_pubspec_yaml) do
        file = updated_files.find { |f| f.name == "pubspec.yaml" }
        YAML.safe_load(file.content, symbolize_names: true)
      end
      subject(:updated_pubspec_lock) do
        file = updated_files.find { |f| f.name == "pubspec.lock" }
        YAML.safe_load(file.content, symbolize_names: true)
      end

      context "with a git dependency" do
        let(:expected_package_yaml) do
          {
            git: {
              url: "git@github.com:dart-lang/path.git",
              ref: "1.8.0"
            }
          }
        end
        let(:expected_package_lock) do
          {
            dependency: "direct main",
            description: {
              path: ".",
              ref: "1.8.0",
              "resolved-ref": "407ab76187fade41c31e39c745b39661b710106c",
              url: "git@github.com:dart-lang/path.git"
            },
            source: "git",
            version: "1.8.0"
          }
        end

        it "updates the yaml file" do
          expect(updated_pubspec_yaml[:dependencies][:path]).to eq(expected_package_yaml)
        end

        it "updates the lock file" do
          expect(updated_pubspec_lock[:packages][:path]).to eq(expected_package_lock)
        end
      end

      context "with a hosted dependency" do
        let(:pubspec_fixture_name) { "hosted" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "path",
            version: "1.8.0",
            previous_version: "1.7.0",
            requirements: [{
              requirement: "^1.8.0",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "hosted",
                url: "https://pub.dartlang.org"
              }
            }],
            previous_requirements: [{
              requirement: "^1.7.0",
              groups: ["dependencies"],
              file: "pubspec.yaml",
              source: {
                type: "hosted",
                url: "https://pub.dartlang.org"
              }
            }],
            package_manager: "pub"
          )
        end

        let(:expected_package_yaml) { "^1.8.0" }
        let(:expected_package_lock) do
          {
            dependency: "direct main",
            description: {
              name: "path",
              url: "https://pub.dartlang.org"
            },
            source: "hosted",
            version: "1.8.0"
          }
        end

        it "updates the yaml file" do
          expect(updated_pubspec_yaml[:dependencies][:path]).to eq(expected_package_yaml)
        end

        it "updates the lock file" do
          expect(updated_pubspec_lock[:packages][:path]).to eq(expected_package_lock)
        end
      end
    end

    describe "with unchanged dependencies" do
      let(:pubspec_fixture_name) { "hosted" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "path",
          version: "1.7.0",
          previous_version: "1.7.0",
          requirements: [{
            requirement: "^1.7.0",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dartlang.org"
            }
          }],
          previous_requirements: [{
            requirement: "^1.7.0",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dev"
            }
          }],
          package_manager: "pub"
        )
      end

      it "raises an error" do
        expect { updater.updated_dependency_files }.to raise_error(RuntimeError, "Content didn't change!")
      end
    end
  end
end
