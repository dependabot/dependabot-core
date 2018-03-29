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
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: package_json_body,
      name: "package.json"
    )
  end
  let(:package_json_body) do
    fixture("javascript", "package_files", manifest_fixture_name)
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: package_lock_body
    )
  end
  let(:package_lock_body) do
    fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lock_body
    )
  end
  let(:yarn_lock_body) do
    fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
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
      let(:manifest_fixture_name) { "yanked_version.json" }
      let(:npm_lock_fixture_name) { "yanked_version.json" }
      it "raises a helpful error" do
        expect { updated_files }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a git dependency that can't be cloned" do
      let(:manifest_fixture_name) { "git_dependency_unreachable.json" }
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

      context "with a package-json.lock" do
        let(:files) { [package_json, package_lock] }
        let(:npm_lock_fixture_name) { "git_dependency_unreachable.json" }

        it "raises a helpful error" do
          expect { updated_files }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls).
                to eq(["https://github.com/greysteil/is-number.git"])
            end
        end
      end
    end

    context "when the lockfile wouldn't update unless cleaned up (Yarn bug)" do
      let(:files) { [package_json, yarn_lock] }
      let(:manifest_fixture_name) { "no_lockfile_change.json" }
      let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }
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

      it "removes details of the old version" do
        expect(updated_files.find { |f| f.name == "yarn.lock" }.content).
          to_not include("babel-register@^6.24.1:")
      end
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

        let(:manifest_fixture_name) { "github_dependency_no_ref.json" }
        let(:yarn_lock_fixture_name) { "github_dependency_no_ref.lock" }
        let(:npm_lock_fixture_name) { "github_dependency_no_ref.json" }

        it "only updates the lockfile" do
          expect(updated_files.map(&:name)).
            to match_array(%w(package-lock.json yarn.lock))

          package_lock =
            updated_files.find { |f| f.name == "package-lock.json" }
          parsed_package_lock = JSON.parse(package_lock.content)
          expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
            to eq("github:jonschlinkert/is-number#"\
                  "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          yarn_lock = updated_files.find { |f| f.name == "yarn.lock" }
          expect(yarn_lock.content).to include("is-number")
          expect(yarn_lock.content).to_not include("d5ac0584ee")
        end

        context "specified as a full URL" do
          let(:req) { nil }
          let(:ref) { "master" }
          let(:old_req) { nil }
          let(:old_ref) { "master" }

          let(:manifest_fixture_name) { "git_dependency.json" }
          let(:yarn_lock_fixture_name) { "git_dependency.lock" }
          let(:npm_lock_fixture_name) { "git_dependency.json" }

          it "only updates the lockfile" do
            expect(updated_files.map(&:name)).
              to match_array(%w(package-lock.json yarn.lock))

            package_lock =
              updated_files.find { |f| f.name == "package-lock.json" }
            parsed_package_lock = JSON.parse(package_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
            yarn_lock = updated_files.find { |f| f.name == "yarn.lock" }
            expect(yarn_lock.content).to include("is-number")
            expect(yarn_lock.content).to_not include("af885e2e890")
          end

          context "when updating another dependency" do
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "chalk",
                version: "2.3.2",
                previous_version: "0.4.0",
                package_manager: "npm_and_yarn",
                requirements: [{
                  requirement: "2.3.2",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }],
                previous_requirements: [{
                  requirement: "0.4.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end

            it "doesn't remove the git dependency" do
              expect(updated_files.map(&:name)).
                to match_array(%w(package.json package-lock.json yarn.lock))

              package_lock =
                updated_files.find { |f| f.name == "package-lock.json" }
              parsed_npm_lock = JSON.parse(package_lock.content)
              expect(parsed_npm_lock["dependencies"]["is-number"]["version"]).
                to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                      "af885e2e890b9ef0875edd2b117305119ee5bdc5")
              yarn_lock = updated_files.find { |f| f.name == "yarn.lock" }
              expect(yarn_lock.content).to include("is-number.git#af885")
            end
          end
        end
      end

      context "with a requirement" do
        let(:files) { [package_json, package_lock] }
        let(:req) { "^4.0.0" }
        let(:ref) { "master" }
        let(:old_req) { "^2.0.0" }
        let(:old_ref) { "master" }

        let(:manifest_fixture_name) { "github_dependency_semver.json" }
        let(:npm_lock_fixture_name) { "github_dependency_semver.json" }

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

        let(:manifest_fixture_name) { "github_dependency.json" }
        let(:yarn_lock_fixture_name) { "github_dependency.lock" }
        let(:npm_lock_fixture_name) { "github_dependency.json" }

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

        context "when using full git URL" do
          let(:manifest_fixture_name) { "git_dependency_ref.json" }
          let(:yarn_lock_fixture_name) { "git_dependency_ref.lock" }
          let(:npm_lock_fixture_name) { "git_dependency_ref.json" }

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
              to eq("https://github.com/jonschlinkert/is-number.git#4.0.0")

            parsed_package_lock = JSON.parse(package_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("git+https://github.com/jonschlinkert/is-number.git#"\
                    "0c6b15a88bc10cd47f67a09506399dfc9ddc075d")

            expect(yarn_lock.content).
              to include("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end

        context "updating to use the registry" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "is-number",
              version: "4.0.0",
              previous_version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
              package_manager: "npm_and_yarn",
              requirements: [
                {
                  requirement: "^4.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number",
                    branch: nil,
                    ref: "d5ac058"
                  }
                }
              ]
            )
          end

          let(:manifest_fixture_name) { "git_dependency_commit_ref.json" }
          let(:yarn_lock_fixture_name) { "git_dependency_commit_ref.lock" }
          let(:npm_lock_fixture_name) { "git_dependency_commit_ref.json" }

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
              to eq("^4.0.0")

            parsed_package_lock = JSON.parse(package_lock.content)
            expect(parsed_package_lock["dependencies"]["is-number"]["version"]).
              to eq("4.0.0")

            expect(yarn_lock.content).
              to include("is-number@^4.0.0")
          end
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
        let(:manifest_fixture_name) { "minor_version_specified.json" }

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
        let(:manifest_fixture_name) { "wildcard.json" }
        let(:yarn_lock_fixture_name) { "wildcard.lock" }

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
        let(:manifest_fixture_name) { "package.json" }

        it "updates the existing development declaration" do
          parsed_file = JSON.parse(updated_package_json_file.content)
          expect(parsed_file.dig("dependencies", "etag")).to be_nil
          expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
        end
      end

      context "when the dependency is specified as both dev and runtime" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.2.1",
            package_manager: "npm_and_yarn",
            requirements: [
              {
                requirement: "0.2.x",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              },
              {
                requirement: "^0.2.0",
                file: "package.json",
                groups: ["devDependencies"],
                source: nil
              }
            ],
            previous_requirements: [
              {
                requirement: "0.1.x",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              },
              {
                requirement: "^0.1.0",
                file: "package.json",
                groups: ["devDependencies"],
                source: nil
              }
            ]
          )
        end
        let(:manifest_fixture_name) { "duplicate.json" }

        it "updates both declarations" do
          parsed_file = JSON.parse(updated_package_json_file.content)
          expect(parsed_file.dig("dependencies", "fetch-factory")).
            to eq("0.2.x")
          expect(parsed_file.dig("devDependencies", "fetch-factory")).
            to eq("^0.2.0")
        end

        context "with identical versions" do
          let(:manifest_fixture_name) { "duplicate_identical.json" }

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "fetch-factory",
              version: "0.2.1",
              package_manager: "npm_and_yarn",
              requirements: [
                {
                  requirement: "^0.2.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                },
                {
                  requirement: "^0.2.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }
              ],
              previous_requirements: [
                {
                  requirement: "^0.1.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                },
                {
                  requirement: "^0.1.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }
              ]
            )
          end

          it "updates both declarations" do
            parsed_file = JSON.parse(updated_package_json_file.content)
            expect(parsed_file.dig("dependencies", "fetch-factory")).
              to eq("^0.2.0")
            expect(parsed_file.dig("devDependencies", "fetch-factory")).
              to eq("^0.2.0")
          end
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, yarn_lock, path_dep] }
        let(:manifest_fixture_name) { "path_dependency.json" }
        let(:npm_lock_fixture_name) { "path_dependency.json" }
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
            [{ "registry" => "registry.npmjs.org", "token" => "secret_token" }]
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
        let(:manifest_fixture_name) { "non_standard_whitespace.json" }

        its(:content) do
          is_expected.to include %("*.js": ["eslint --fix", "git add"])
        end
      end

      context "with Yarn workspaces" do
        let(:files) { [package_json, yarn_lock, package1, other_package] }
        let(:manifest_fixture_name) { "workspaces.json" }
        let(:yarn_lock_fixture_name) { "workspaces.lock" }
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
        let(:manifest_fixture_name) { "path_dependency.json" }
        let(:npm_lock_fixture_name) { "path_dependency.json" }
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
        let(:manifest_fixture_name) { "dist_tag.json" }
        let(:yarn_lock_fixture_name) { "dist_tag.lock" }

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("bootstrap@next:\n  version \"4.0.0-beta.3\"")
        end
      end

      context "when the version is missing from the lockfile" do
        let(:yarn_lock_fixture_name) { "missing_requirement.lock" }

        it "has details of the updated item (doesn't error)" do
          expect(updated_yarn_lock_file.content).
            to include("fetch-factory@^0.0.2")
        end
      end

      context "with a path-based dependency" do
        let(:files) { [package_json, yarn_lock, path_dep] }
        let(:manifest_fixture_name) { "path_dependency.json" }
        let(:yarn_lock_fixture_name) { "path_dependency.lock" }
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
        let(:manifest_fixture_name) { "wildcard.json" }
        let(:yarn_lock_fixture_name) { "wildcard.lock" }

        it "has details of the updated item" do
          expect(updated_yarn_lock_file.content).
            to include("fetch-factory@*:\n  version \"0.2.1\"")
        end
      end

      context "when updating only the lockfile" do
        let(:files) { [package_json, yarn_lock] }
        let(:manifest_fixture_name) { "lockfile_only_change.json" }
        let(:yarn_lock_fixture_name) { "lockfile_only_change.lock" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "babel-jest",
            version: "22.4.3",
            previous_version: "22.0.4",
            package_manager: "npm_and_yarn",
            requirements: [
              {
                file: "package.json",
                requirement: "^22.0.4",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "package.json",
                requirement: "^22.0.4",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "has details of the updated item, but doesn't update everything" do
          # Updates the desired dependency
          expect(updated_yarn_lock_file.content).
            to include("babel-jest@^22.0.4:\n  version \"22.4.3\"")

          # Doesn't update unrelated dependencies
          expect(updated_yarn_lock_file.content).
            to include("eslint@^4.14.0:\n  version \"4.14.0\"")
        end
      end

      context "with workspaces" do
        let(:files) { [package_json, yarn_lock, package1, other_package] }
        let(:manifest_fixture_name) { "workspaces.json" }
        let(:yarn_lock_fixture_name) { "workspaces.lock" }
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
