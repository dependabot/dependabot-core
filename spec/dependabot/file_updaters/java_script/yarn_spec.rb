# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java_script/yarn"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::JavaScript::Yarn do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:files) { [package_json, lockfile] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: package_json_body,
      name: "package.json"
    )
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", "package.json")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: lockfile_body
    )
  end
  let(:lockfile_body) { fixture("javascript", "yarn_lockfiles", "yarn.lock") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "fetch-factory",
      version: "0.0.2",
      package_manager: "yarn",
      requirements: [
        { file: "package.json", requirement: "^0.0.1", groups: [], source: nil }
      ]
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    specify { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(2) }

    describe "the updated package_json_file" do
      subject(:updated_package_json_file) do
        updated_files.find { |f| f.name == "package.json" }
      end

      its(:content) { is_expected.to include "{{ name }}" }
      its(:content) { is_expected.to include "\"fetch-factory\": \"^0.0.2\"" }
      its(:content) { is_expected.to include "\"etag\": \"^1.0.0\"" }

      context "when the minor version is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.2.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "0.1.x",
                groups: [],
                source: nil
              }
            ]
          )
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "minor_version_specified.json")
        end

        its(:content) { is_expected.to include "\"fetch-factory\": \"0.2.x\"" }
      end

      context "when a wildcard is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.2.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "*",
                groups: [],
                source: nil
              }
            ]
          )
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "wildcard.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "wildcard.lock")
        end

        it "only updates the lockfile" do
          expect(updated_files.map(&:name)).to eq(["yarn.lock"])
        end
      end

      context "when a dev dependency is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.8.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: nil
              }
            ]
          )
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "package.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "yarn.lock")
        end

        it "updates the existing development declaration" do
          parsed_file = JSON.parse(updated_package_json_file.content)
          expect(parsed_file.dig("dependencies", "etag")).to be_nil
          expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, lockfile, path_dep] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "path_dependency.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "path_dependency.lock")
        end
        let(:path_dep) do
          Dependabot::DependencyFile.new(
            name: "deps/etag/package.json",
            content: fixture("javascript", "package_files", "etag.json")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "1.3.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              }
            ]
          )
        end

        its(:content) { is_expected.to include "\"lodash\": \"^1.3.1\"" }
        its(:content) do
          is_expected.to include "\"etag\": \"file:./deps/etag\""
        end
      end

      context "with workspaces" do
        let(:files) { [package_json, lockfile, package1, other_package] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "workspaces.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "workspaces.lock")
        end
        let(:package1) do
          Dependabot::DependencyFile.new(
            name: "packages/package1/package.json",
            content: fixture("javascript", "package_files", "package1.json")
          )
        end
        let(:other_package) do
          Dependabot::DependencyFile.new(
            name: "other_package/package.json",
            content: other_package_body
          )
        end
        let(:other_package_body) do
          fixture("javascript", "package_files", "other_package.json")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "1.3.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.2.0",
                groups: [],
                source: nil
              },
              {
                file: "packages/package1/package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              },
              {
                file: "other_package/package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "updates the three package.json files" do
          package = updated_files.find { |f| f.name == "package.json" }
          package1 = updated_files.find do |f|
            f.name == "packages/package1/package.json"
          end
          other_package = updated_files.find do |f|
            f.name == "other_package/package.json"
          end
          expect(package.content).to include("\"lodash\": \"^1.3.1\"")
          expect(package1.content).to include("\"lodash\": \"^1.3.1\"")
          expect(other_package.content).to include("\"lodash\": \"^1.3.1\"")
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "chalk",
              version: "0.4.0",
              package_manager: "yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.4.0",
                  groups: [],
                  source: nil
                }
              ]
            )
          end

          it "updates the right file" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))
          end
        end

        context "with a dependency that appears as a development dependency" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "etag",
              version: "1.8.1",
              package_manager: "yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "^1.1.0",
                  groups: ["devDependencies"],
                  source: nil
                }
              ]
            )
          end

          it "updates the right file" do
            expect(updated_files.map(&:name)).
              to match_array(%w(yarn.lock packages/package1/package.json))
          end

          it "updates the existing development declaration" do
            file = updated_files.find do |f|
              f.name == "packages/package1/package.json"
            end
            parsed_file = JSON.parse(file.content)
            expect(parsed_file.dig("dependencies", "etag")).to be_nil
            expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
          end
        end
      end
    end

    describe "the updated yarn_lock" do
      subject(:updated_yarn_lock_file) do
        updated_files.find { |f| f.name == "yarn.lock" }
      end

      it "has details of the updated item" do
        expect(updated_yarn_lock_file.content).
          to include("fetch-factory@^0.0.2")
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, lockfile, path_dep] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "path_dependency.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "path_dependency.lock")
        end
        let(:path_dep) do
          Dependabot::DependencyFile.new(
            name: "deps/etag/package.json",
            content: fixture("javascript", "package_files", "etag.json")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "1.3.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("lodash@^1.3.1")
        end
      end

      context "when a wildcard is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.2.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "*",
                groups: [],
                source: nil
              }
            ]
          )
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "wildcard.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "wildcard.lock")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("fetch-factory@*:\n  version \"0.2.1\"")
        end
      end

      context "with workspaces" do
        let(:files) { [package_json, lockfile, package1, other_package] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "workspaces.json")
        end
        let(:lockfile_body) do
          fixture("javascript", "yarn_lockfiles", "workspaces.lock")
        end
        let(:package1) do
          Dependabot::DependencyFile.new(
            name: "packages/package1/package.json",
            content: fixture("javascript", "package_files", "package1.json")
          )
        end
        let(:other_package) do
          Dependabot::DependencyFile.new(
            name: "other_package/package.json",
            content: other_package_body
          )
        end
        let(:other_package_body) do
          fixture("javascript", "package_files", "other_package.json")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "lodash",
            version: "1.3.1",
            package_manager: "yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.2.0",
                groups: [],
                source: nil
              },
              {
                file: "packages/package1/package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              },
              {
                file: "other_package/package.json",
                requirement: "^1.2.1",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "updates the yarn.lock based on all three package.jsons" do
          lockfile = updated_files.find { |f| f.name == "yarn.lock" }
          expect(lockfile.content).to include("lodash@^1.3.1:")
          expect(lockfile.content).to_not include("lodash@^1.2.1:")
          expect(lockfile.content).to_not include("workspace-aggregator")
        end

        context "with a dependency that doesn't appear in all the workspaces" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "chalk",
              version: "0.4.0",
              package_manager: "yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.4.0",
                  groups: [],
                  source: nil
                }
              ]
            )
          end

          it "updates the yarn.lock" do
            lockfile = updated_files.find { |f| f.name == "yarn.lock" }
            expect(lockfile.content).to include("chalk@0.4.0:")
            expect(lockfile.content).to_not include("workspace-aggregator")
          end
        end
      end
    end
  end
end
