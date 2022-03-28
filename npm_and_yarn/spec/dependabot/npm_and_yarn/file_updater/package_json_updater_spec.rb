# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_updater/package_json_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PackageJsonUpdater do
  let(:package_json_updater) do
    described_class.new(
      package_json: package_json,
      dependencies: dependencies
    )
  end

  let(:package_json) do
    project_dependency_files(project_name).find { |f| f.name == "package.json" }
  end
  let(:project_name) { "npm8/simple" }

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "fetch-factory",
      version: "0.0.2",
      package_manager: "npm_and_yarn",
      requirements: [{
        file: "package.json",
        requirement: "^0.0.2",
        groups: ["dependencies"],
        source: nil
      }],
      previous_requirements: [{
        file: "package.json",
        requirement: "^0.0.1",
        groups: ["dependencies"],
        source: nil
      }]
    )
  end

  describe "#updated_package_json" do
    subject(:updated_package_json) { package_json_updater.updated_package_json }

    its(:content) { is_expected.to include "{{ name }}" }
    its(:content) { is_expected.to include '"fetch-factory": "^0.0.2"' }
    its(:content) { is_expected.to include '"etag" : "^1.0.0"' }

    context "when the minor version is specified" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "fetch-factory",
          version: "0.2.1",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "0.2.x",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "0.1.x",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end
      let(:project_name) { "npm8/minor_version_specified" }

      its(:content) { is_expected.to include '"fetch-factory": "0.2.x"' }
    end

    context "when the requirement hasn't changed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "fetch-factory",
          version: "0.1.5",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "0.1.x",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "0.1.x",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end
      let(:project_name) { "npm8/minor_version_specified" }

      its(:content) do
        is_expected.to eq(fixture("projects", "npm8", "minor_version_specified", "package.json"))
      end

      context "except for the source" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.1.5",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "0.1.x",
              groups: ["dependencies"],
              source: {
                type: "registry",
                url: "http://registry.npm.taobao.org"
              }
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "0.1.x",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        its(:content) do
          is_expected.to eq(fixture("projects", "npm8", "minor_version_specified", "package.json"))
        end
      end
    end

    context "when a dev dependency is specified" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.8.1",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^1.8.1",
            groups: ["devDependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }]
        )
      end
      let(:project_name) { "npm8/simple" }

      it "updates the existing development declaration" do
        parsed_file = JSON.parse(updated_package_json.content)
        expect(parsed_file.dig("dependencies", "etag")).to be_nil
        expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
      end
    end

    context "updating multiple dependencies" do
      let(:project_name) { "npm8/simple" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.0.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^0.0.2",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^0.0.1",
              groups: ["dependencies"],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.8.1",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^1.8.1",
              groups: ["devDependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: ["devDependencies"],
              source: nil
            }]
          )
        ]
      end

      it "updates both dependency declarations" do
        parsed_file = JSON.parse(updated_package_json.content)
        expect(parsed_file.dig("dependencies", "etag")).to be_nil
        expect(parsed_file.dig("devDependencies", "etag")).to eq("^1.8.1")
        expect(parsed_file.dig("dependencies", "fetch-factory")).to eq("^0.0.2")
      end
    end

    context "when the dependency is specified as both dev and runtime" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "fetch-factory",
          version: "0.2.1",
          package_manager: "npm_and_yarn",
          requirements: [{
            requirement: "0.2.x",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }, {
            requirement: "^0.2.0",
            file: "package.json",
            groups: ["devDependencies"],
            source: nil
          }],
          previous_requirements: [{
            requirement: "0.1.x",
            file: "package.json",
            groups: ["dependencies"],
            source: nil
          }, {
            requirement: "^0.1.0",
            file: "package.json",
            groups: ["devDependencies"],
            source: nil
          }]
        )
      end
      let(:project_name) { "npm6/duplicate" }

      it "updates both declarations" do
        parsed_file = JSON.parse(updated_package_json.content)
        expect(parsed_file.dig("dependencies", "fetch-factory")).
          to eq("0.2.x")
        expect(parsed_file.dig("devDependencies", "fetch-factory")).
          to eq("^0.2.0")
      end

      context "with identical versions" do
        let(:project_name) { "npm8/duplicate_identical" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.2.1",
            package_manager: "npm_and_yarn",
            requirements: [{
              requirement: "^0.2.0",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "^0.2.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: nil
            }],
            previous_requirements: [{
              requirement: "^0.1.0",
              file: "package.json",
              groups: ["dependencies"],
              source: nil
            }, {
              requirement: "^0.1.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: nil
            }]
          )
        end

        it "updates both declarations" do
          parsed_file = JSON.parse(updated_package_json.content)
          expect(parsed_file.dig("dependencies", "fetch-factory")).
            to eq("^0.2.0")
          expect(parsed_file.dig("devDependencies", "fetch-factory")).
            to eq("^0.2.0")
        end
      end
    end

    context "when the dependency is specified as both dev and peer" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "2.0.0",
          package_manager: "npm_and_yarn",
          requirements: [{
            requirement: "^2.0.0",
            file: "package.json",
            groups: ["devDependencies"],
            source: nil
          }],
          previous_requirements: [{
            requirement: "^1.0.0",
            file: "package.json",
            groups: ["devDependencies"],
            source: nil
          }]
        )
      end
      let(:project_name) { "npm8/dev_and_peer_dependency" }

      it "updates both declarations" do
        parsed_file = JSON.parse(updated_package_json.content)
        expect(parsed_file.dig("devDependencies", "etag")).
          to eq("^2.0.0")
        expect(parsed_file.dig("peerDependencies", "etag")).
          to eq("^2.0.0")
      end
    end

    context "with a git dependency" do
      let(:project_name) { "npm8/github_dependency" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
          package_manager: "npm_and_yarn",
          requirements: [{
            requirement: nil,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "4.0.0"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "2.0.0"
            }
          }]
        )
      end

      its(:content) { is_expected.to include("jonschlinkert/is-number#4.0.0") }

      context "that specifies a semver requirement" do
        let(:project_name) { "npm8/github_dependency_semver" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "is-number",
            version: "4.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              requirement: "^4.0.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "master"
              }
            }],
            previous_requirements: [{
              requirement: "^2.0.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: "master"
              }
            }]
          )
        end

        its(:content) do
          is_expected.to include('"jonschlinkert/is-number#semver:^4.0.0"')
        end

        context "without the `semver:` marker" do
          let(:project_name) { "yarn/github_dependency_yarn_semver" }

          its(:content) do
            is_expected.to include('"jonschlinkert/is-number#^4.0.0"')
          end
        end
      end
    end

    context "with a path-based dependency" do
      let(:project_name) { "npm8/path_dependency" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "1.3.1",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^1.3.1",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^1.2.1",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end

      its(:content) { is_expected.to include '"lodash": "^1.3.1"' }
      its(:content) do
        is_expected.to include '"etag": "file:./deps/etag"'
      end
    end

    context "with non-standard whitespace" do
      let(:project_name) { "npm8/non_standard_whitespace" }

      its(:content) do
        is_expected.to include %("*.js": ["eslint --fix", "git add"])
      end
    end
  end
end
