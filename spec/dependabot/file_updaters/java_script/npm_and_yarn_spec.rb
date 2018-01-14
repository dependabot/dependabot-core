# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java_script/npm_and_yarn"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::JavaScript::NpmAndYarn do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [package_json, yarn_lock, package_lock] }
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: package_json_body,
      name: "package.json"
    )
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", "package.json")
  end
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: package_lock_body
    )
  end
  let(:package_lock_body) do
    fixture("javascript", "npm_lockfiles", "package-lock.json")
  end
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lock_body
    )
  end
  let(:yarn_lock_body) do
    fixture("javascript", "yarn_lockfiles", "yarn.lock")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "fetch-factory",
      version: "0.0.2",
      package_manager: "npm_and_yarn",
      requirements: [
        { file: "package.json", requirement: "^0.0.2", groups: [], source: nil }
      ],
      previous_requirements: [
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
    its(:length) { is_expected.to eq(3) }

    context "without a package-lock.json or yarn.lock" do
      let(:files) { [package_json] }
      its(:length) { is_expected.to eq(1) }
    end

    context "with a dependency version that can't be found" do
      let(:package_json_body) do
        fixture("javascript", "package_files", "yanked_version.json")
      end
      let(:package_lock_body) do
        fixture("javascript", "npm_lockfiles", "yanked_version.json")
      end
      it "raises a helpful error" do
        expect { updated_files }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the lockfile doesn't update (due to a Yarn bug)" do
      let(:files) { [package_json, yarn_lock] }
      let(:package_json_body) do
        fixture("javascript", "package_files", "no_lockfile_change.json")
      end
      let(:yarn_lock_body) do
        fixture("javascript", "yarn_lockfiles", "no_lockfile_change.lock")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "babel-register",
          version: "6.26.0",
          package_manager: "npm_and_yarn",
          requirements: [
            {
              file: "package.json",
              requirement: "^6.26.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "package.json",
              requirement: "^6.24.1",
              groups: [],
              source: nil
            }
          ]
        )
      end

      # This occurs because a Yarn bug prevents Yarn from cleaning up the
      # lockfile properly. If the bug is ever fixed then the below will equal
      # two. In the meantime, this spec ensures we don't raise errors.
      its(:length) { is_expected.to eq(1) }
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: version,
          previous_version: previous_version,
          package_manager: "npm_and_yarn",
          requirements: [
            {
              requirement: req,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: ref
              }
            }
          ],
          previous_requirements: [
            {
              requirement: old_req,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: old_ref
              }
            }
          ]
        )
      end
      let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

      context "without a requirement or reference" do
        let(:req) { nil }
        let(:ref) { "master" }
        let(:old_req) { nil }
        let(:old_ref) { "master" }

        let(:package_json_body) do
          fixture "javascript", "package_files", "github_dependency_no_ref.json"
        end
        let(:package_lock_body) do
          fixture "javascript", "npm_lockfiles", "github_dependency_no_ref.json"
        end
        let(:yarn_lock_body) do
          fixture(
            "javascript",
            "yarn_lockfiles",
            "github_dependency_no_ref.lock"
          )
        end

        it "only updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json yarn.lock))

          package_lock =
            updated_files.find { |f| f.name == "package-lock.json" }
          parsed_package_lock = JSON.parse(package_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a requirement" do
        let(:files) { [package_json, package_lock] }
        let(:req) { "^4.0.0" }
        let(:ref) { "master" }
        let(:old_req) { "^2.0.0" }
        let(:old_ref) { "master" }

        let(:package_json_body) do
          fixture "javascript", "package_files", "github_dependency_semver.json"
        end
        let(:package_lock_body) do
          fixture "javascript", "npm_lockfiles", "github_dependency_semver.json"
        end

        it "updates the package.json and the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json))

          package_json =
            updated_files.find { |f| f.name == "package.json" }
          package_lock =
            updated_files.find { |f| f.name == "package-lock.json" }

          parsed_package_json = JSON.parse(package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#semver:^4.0.0")

          parsed_package_lock = JSON.parse(package_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a reference" do
        let(:req) { nil }
        let(:ref) { "4.0.0" }
        let(:old_req) { nil }
        let(:old_ref) { "2.0.0" }

        let(:package_json_body) do
          fixture("javascript", "package_files", "github_dependency.json")
        end
        let(:package_lock_body) do
          fixture("javascript", "npm_lockfiles", "github_dependency.json")
        end
        let(:yarn_lock_body) do
          fixture("javascript", "yarn_lockfiles", "github_dependency.lock")
        end

        it "updates the package.json and the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package.json package-lock.json yarn.lock))

          package_json =
            updated_files.find { |f| f.name == "package.json" }
          package_lock =
            updated_files.find { |f| f.name == "package-lock.json" }
          yarn_lock =
            updated_files.find { |f| f.name == "yarn.lock" }

          parsed_package_json = JSON.parse(package_json.content)
          expect(parsed_package_json["devDependencies"]["is-number"]).
            to eq("jonschlinkert/is-number#4.0.0")

          parsed_package_lock = JSON.parse(package_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

          expect(yarn_lock.content).
            to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end
    end

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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "0.2.x",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "*",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
        let(:yarn_lock_body) do
          fixture("javascript", "yarn_lockfiles", "wildcard.lock")
        end

        it "only updates the lockfiles" do
          expect(updated_files.map(&:name)).
            to match_array(%w(yarn.lock package-lock.json))
        end
      end

      context "when a dev dependency is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.8.1",
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.8.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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

        it "updates the existing development declaration" do
          parsed_file = JSON.parse(updated_package_json_file.content)
          expect(parsed_file.dig("dependencies", "etag")).to be_nil
          expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, yarn_lock, path_dep] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "path_dependency.json")
        end
        let(:package_lock_body) do
          fixture("javascript", "npm_lockfiles", "path_dependency.json")
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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

      context "with a .npmrc" do
        let(:files) { [package_json, yarn_lock, npmrc] }
        let(:npmrc) do
          Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: fixture("javascript", "npmrc", "env_auth_token")
          )
        end

        its(:content) { is_expected.to include "\"etag\": \"^1.0.0\"" }

        context "that has an _auth line" do
          let(:npmrc) do
            Dependabot::DependencyFile.new(
              name: ".npmrc",
              content: fixture("javascript", "npmrc", "env_global_auth")
            )
          end

          let(:credentials) do
            [
              {
                "registry" => "registry.npmjs.org",
                "token" => "secret_token"
              }
            ]
          end

          its(:content) do
            is_expected.to include "\"fetch-factory\": \"^0.0.2\""
          end
        end
      end

      context "without a package-lock.json or yarn.lock" do
        let(:files) { [package_json] }

        its(:content) { is_expected.to include "{{ name }}" }
        its(:content) { is_expected.to include "\"fetch-factory\": \"^0.0.2\"" }
        its(:content) { is_expected.to include "\"etag\": \"^1.0.0\"" }
      end

      context "with non-standard whitespace" do
        let(:package_json_body) do
          fixture("javascript", "package_files", "non_standard_whitespace.json")
        end

        its(:content) do
          is_expected.to include %("*.js": ["eslint --fix", "git add"])
        end
      end

      context "with Yarn workspaces" do
        let(:files) { [package_json, yarn_lock, package1, other_package] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "workspaces.json")
        end
        let(:yarn_lock_body) do
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              },
              {
                file: "packages/package1/package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              },
              {
                file: "other_package/package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
              package_manager: "npm_and_yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.4.0",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.3.0",
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
              package_manager: "npm_and_yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "^1.8.1",
                  groups: ["devDependencies"],
                  source: nil
                }
              ],
              previous_requirements: [
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

    describe "the updated package-lock.json" do
      subject(:updated_lockfile) do
        updated_files.find { |f| f.name == "package-lock.json" }
      end

      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_lockfile.content)
        expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
          to eq("0.0.2")
      end

      context "when the requirement has not been updated" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.0.2",
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^0.0.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "package.json",
                requirement: "^0.0.1",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "has details of the updated item" do
          parsed_lockfile = JSON.parse(updated_lockfile.content)
          expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, package_lock, path_dep] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "path_dependency.json")
        end
        let(:package_lock_body) do
          fixture("javascript", "npm_lockfiles", "path_dependency.json")
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
          parsed_lockfile = JSON.parse(updated_lockfile.content)
          expect(parsed_lockfile["dependencies"]["lodash"]["version"]).
            to eq("1.3.1")
        end
      end

      context "with a .npmrc that precludes updates to the lockfile" do
        let(:files) { [package_json, package_lock, npmrc] }

        let(:npmrc) do
          Dependabot::DependencyFile.new(
            name: ".npmrc",
            content: fixture("javascript", "npmrc", "no_lockfile")
          )
        end

        it { is_expected.to be_nil }
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

      context "when a dist-tag is specified" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "bootstrap",
            version: "4.0.0-beta.3",
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "next",
                groups: [],
                source: nil
              }
            ],
            previous_version: "3.3.7",
            previous_requirements: [
              {
                file: "package.json",
                requirement: "next",
                groups: [],
                source: nil
              }
            ]
          )
        end
        let(:package_json_body) do
          fixture("javascript", "package_files", "dist_tag.json")
        end
        let(:yarn_lock_body) do
          fixture("javascript", "yarn_lockfiles", "dist_tag.lock")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("bootstrap@next:\n  version \"4.0.0-beta.3\"")
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, yarn_lock, path_dep] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "path_dependency.json")
        end
        let(:yarn_lock_body) do
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "*",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
        let(:yarn_lock_body) do
          fixture("javascript", "yarn_lockfiles", "wildcard.lock")
        end

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("fetch-factory@*:\n  version \"0.2.1\"")
        end
      end

      context "with workspaces" do
        let(:files) { [package_json, yarn_lock, package1, other_package] }
        let(:package_json_body) do
          fixture("javascript", "package_files", "workspaces.json")
        end
        let(:yarn_lock_body) do
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
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              },
              {
                file: "packages/package1/package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              },
              {
                file: "other_package/package.json",
                requirement: "^1.3.1",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
              package_manager: "npm_and_yarn",
              requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.4.0",
                  groups: [],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  file: "packages/package1/package.json",
                  requirement: "0.3.0",
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
