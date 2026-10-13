# typed: false
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

      context "when not changed for the source" do
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

    context "when updating multiple dependencies" do
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

    context "when updating multiple dependencies that results in 'package.json' update only once" do
      let(:project_name) { "npm8/simple_with_multiple_deps" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "cross-spawn",
            version: "^7.0.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^7.0.6",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^7.0.2",
              groups: ["dependencies"],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "dep-spawn",
            version: "^6.0.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^6.0.2",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^6.0.1",
              groups: ["dependencies"],
              source: nil
            }]
          )
        ]
      end

      it "updates both dependency declarations" do
        expect { updated_package_json }
          .to raise_error("Expected content to change!")
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
        expect(parsed_file.dig("dependencies", "fetch-factory"))
          .to eq("0.2.x")
        expect(parsed_file.dig("devDependencies", "fetch-factory"))
          .to eq("^0.2.0")
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
          expect(parsed_file.dig("dependencies", "fetch-factory"))
            .to eq("^0.2.0")
          expect(parsed_file.dig("devDependencies", "fetch-factory"))
            .to eq("^0.2.0")
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
        expect(parsed_file.dig("devDependencies", "etag"))
          .to eq("^2.0.0")
        expect(parsed_file.dig("peerDependencies", "etag"))
          .to eq("^2.0.0")
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

      context "when it specifies a semver requirement" do
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

    context "with a path-based dependency that is in dependency list" do
      let(:project_name) { "npm8/path_dependency" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "file:./deps/etag",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^file:./deps/etag",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "file:./deps/etag",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end

      it "exits update with relevant exception" do
        expect { updated_package_json }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a patched dependency that is in dependency list" do
      let(:project_name) { "npm8/path_dependency" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "patch:./deps/etag",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "patch:./deps/etag",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "patch:./deps/etag",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end

      it "exits update with relevant exception" do
        expect { updated_package_json }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with npm overrides" do
      let(:project_name) { "npm8/simple_with_overrides" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "3.10.1",
          previous_version: "3.10.0",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^3.0",
            groups: ["devDependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^3.0",
            groups: ["devDependencies"],
            source: nil
          }]
        )
      end

      it "updates the override, as well as the declaration" do
        parsed = JSON.parse(updated_package_json.content)
        expect(parsed.dig("overrides", "lodash")).to eq("3.10.1")
      end
    end

    context "with npm overrides for a sub-dependency" do
      let(:project_name) { "npm8/subdep_with_override" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "undici",
          version: "6.24.1",
          previous_version: "6.23.0",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end

      it "updates the override preserving the version prefix" do
        parsed = JSON.parse(updated_package_json.content)
        expect(parsed.dig("overrides", "undici")).to eq("^6.24.1")
      end
    end

    context "with npm overrides for a sub-dependency using exact version" do
      let(:package_json) do
        Dependabot::DependencyFile.new(
          name: "package.json",
          content: {
            name: "test",
            version: "1.0.0",
            dependencies: { "@actions/http-client": "^2.2.3" },
            overrides: { undici: "6.23.0" }
          }.to_json
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "undici",
          version: "6.24.1",
          previous_version: "6.23.0",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end

      it "updates the override with the exact version" do
        parsed = JSON.parse(updated_package_json.content)
        expect(parsed.dig("overrides", "undici")).to eq("6.24.1")
      end
    end

    context "with yarn resolutions for a sub-dependency" do
      let(:package_json) do
        Dependabot::DependencyFile.new(
          name: "package.json",
          content: {
            name: "test",
            version: "1.0.0",
            dependencies: { "some-parent": "^1.0.0" },
            resolutions: { undici: "^6.23.0" }
          }.to_json
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "undici",
          version: "6.24.1",
          previous_version: "6.23.0",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end

      it "updates the resolution" do
        parsed = JSON.parse(updated_package_json.content)
        expect(parsed.dig("resolutions", "undici")).to eq("^6.24.1")
      end
    end

    context "with pnpm overrides for a sub-dependency" do
      let(:package_json) do
        Dependabot::DependencyFile.new(
          name: "package.json",
          content: {
            name: "test",
            version: "1.0.0",
            dependencies: { "some-parent": "^1.0.0" },
            pnpm: { overrides: { undici: ">=6.23.0" } }
          }.to_json
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "undici",
          version: "6.24.1",
          previous_version: "6.23.0",
          package_manager: "npm_and_yarn",
          requirements: [],
          previous_requirements: []
        )
      end

      it "updates the pnpm override" do
        parsed = JSON.parse(updated_package_json.content)
        expect(parsed.dig("pnpm", "overrides", "undici")).to eq(">=6.24.1")
      end
    end

    context "with entries in several package.json objects" do
      subject(:updated_content) { updated_package_json.content }

      let(:package_json) { Dependabot::DependencyFile.new(name: "package.json", content: content) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "7.0.0",
          previous_version: "6.0.0",
          package_manager: "npm_and_yarn",
          requirements: groups.map { |group| requirement(group, new_requirement) },
          previous_requirements: groups.map { |group| requirement(group, previous_requirement) }
        )
      end
      let(:dependency_name) { "is-number" }
      let(:groups) { ["dependencies"] }
      let(:previous_requirement) { "6.0.0" }
      let(:new_requirement) { "7.0.0" }
      let(:source) { nil }

      def requirement(group, requirement)
        { file: "package.json", requirement: requirement, groups: [group], source: source }
      end

      context "when a nested dependencies object declares the same requirement" do
        let(:content) do
          <<~JSON
            {
              "pnpm": {
                "packageExtensions": {
                  "left-pad@1": { "dependencies": { "is-number": "6.0.0" } }
                }
              },
              "dependencies": { "is-number": "6.0.0" }
            }
          JSON
        end

        it "updates only the top-level section" do
          expect(updated_content).to eq(
            content.sub(%("dependencies": { "is-number": "6.0.0" }\n}), %("dependencies": { "is-number": "7.0.0" }\n}))
          )
        end
      end

      context "when a compact nested dependencies object precedes the section" do
        let(:content) do
          <<~JSON
            {
              "pnpm": {"packageExtensions":{"left-pad@1":{"dependencies":{"is-number":"6.0.0"}}}},
              "dependencies": {
                "is-number": "6.0.0"
              }
            }
          JSON
        end

        it "updates only the top-level section" do
          expect(updated_content).to eq(content.sub('"is-number": "6.0.0"', '"is-number": "7.0.0"'))
        end
      end

      context "when the dependency is in two sections and the first declaration is compact" do
        let(:groups) { %w(dependencies devDependencies) }
        let(:content) do
          <<~JSON
            {
              "devDependencies": {"is-number":"6.0.0"},
              "dependencies": {
                "is-number": "6.0.0"
              }
            }
          JSON
        end

        it "updates both sections" do
          expect(updated_content).to eq(
            content.sub('"is-number":"6.0.0"', '"is-number":"7.0.0"')
                   .sub('"is-number": "6.0.0"', '"is-number": "7.0.0"')
          )
        end
      end

      context "when the key is written with an escape" do
        let(:content) do
          <<~JSON
            {
              "dependencies": {
                "is-\\u006eumber": "6.0.0"
              }
            }
          JSON
        end

        it "updates the declaration" do
          expect(updated_content).to eq(content.sub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when a compact git declaration moves to a registry requirement" do
        let(:source) { { type: "git", url: "https://github.com/jonschlinkert/is-number", branch: nil, ref: "6.0.0" } }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "7.0.0",
            previous_version: "6.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{ file: "package.json", requirement: "^7.0.0", groups: ["dependencies"], source: nil }],
            previous_requirements: [requirement("dependencies", nil)]
          )
        end
        let(:content) do
          <<~JSON
            {
              "dependencies": {"is-number":"github:jonschlinkert/is-number#6.0.0"}
            }
          JSON
        end

        it "replaces the git reference" do
          expect(updated_content).to eq(content.sub('"github:jonschlinkert/is-number#6.0.0"', '"^7.0.0"'))
        end
      end

      context "with formatting variants" do
        {
          "a minified document" => '{"name":"app","dependencies":{"etag":"1.0.1","is-number":"6.0.0"}}',
          "extra spaces around the colon" => %({\n  "dependencies": {\n    "is-number"  :   "6.0.0"\n  }\n}\n),
          "entries on one line" =>
            %({\n  "dependencies": { "etag": "1.0.1", "is-number": "6.0.0", "left-pad": "1.3.0" }\n}\n),
          "devDependencies before dependencies" =>
            %({\n  "devDependencies": { "etag": "1.0.1" },\n  "dependencies": {\n    "is-number": "6.0.0"\n  }\n}\n),
          "tab indentation" => %({\n\t"dependencies": {\n\t\t"is-number": "6.0.0"\n\t}\n}\n)
        }.each do |description, document|
          context "with #{description}" do
            let(:content) { document }

            it "updates only the requirement" do
              expect(updated_content).to eq(content.sub('"6.0.0"', '"7.0.0"'))
            end
          end
        end
      end

      context "when a peer dependency has the same requirement" do
        let(:groups) { ["devDependencies"] }
        let(:content) do
          <<~JSON
            {
              "peerDependencies": { "is-number": "6.0.0" },
              "devDependencies": { "is-number": "6.0.0" }
            }
          JSON
        end

        it "updates the peer dependency too" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "with resolutions" do
        context "when the resolution pins the previous version" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "resolutions": { "is-number": "6.0.0" }
              }
            JSON
          end

          it "updates the declaration and the resolution" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when pnpm overrides pin the previous version" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "pnpm": { "overrides": { "is-number": "6.0.0" } }
              }
            JSON
          end

          it "updates the declaration and the override" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when top-level overrides pin the previous version" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "overrides": { "is-number": "6.0.0" }
              }
            JSON
          end

          it "updates the declaration and the override" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when unrelated resolutions precede the overrides" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "resolutions": { "etag": "1.0.1" },
                "overrides": { "is-number": "6.0.0" }
              }
            JSON
          end

          it "updates the declaration and the override" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when unrelated resolutions precede pnpm overrides" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "resolutions": { "etag": "1.0.1" },
                "pnpm": { "overrides": { "is-number": "6.0.0" } }
              }
            JSON
          end

          it "updates the declaration and the override" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when the resolution is the previous requirement" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "^6.0.0" },
                "resolutions": { "is-number": "^6.0.0" }
              }
            JSON
          end
          let(:previous_requirement) { "^6.0.0" }
          let(:new_requirement) { "^7.0.0" }

          it "updates the resolution to the new requirement" do
            expect(updated_content).to eq(content.gsub('"^6.0.0"', '"^7.0.0"'))
          end
        end

        context "when resolutions and overrides pin the dependency differently" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "^6.0.0" },
                "resolutions": { "is-number": "^6.0.0" },
                "overrides": { "is-number": "6.0.0" }
              }
            JSON
          end
          let(:previous_requirement) { "^6.0.0" }
          let(:new_requirement) { "^7.0.0" }

          it "updates each entry from its own value" do
            expect(updated_content).to eq(content.gsub('"^6.0.0"', '"^7.0.0"').sub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when the resolution is compact" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "6.0.0" },
                "resolutions": {"etag":"1.0.1","is-number":"6.0.0"}
              }
            JSON
          end

          it "updates the declaration and the resolution" do
            expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when a compact declaration with the same requirement precedes the resolution" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "^6.0.0" },
                "pnpm": {"packageExtensions":{"left-pad@1":{"dependencies":{"is-number":"6.0.0"}}}},
                "resolutions": { "is-number": "6.0.0" }
              }
            JSON
          end
          let(:previous_requirement) { "^6.0.0" }
          let(:new_requirement) { "^7.0.0" }

          it "updates the resolution" do
            expect(updated_content).to eq(
              content.sub('"^6.0.0"', '"^7.0.0"').sub('"is-number": "6.0.0"', '"is-number": "7.0.0"')
            )
          end
        end

        context "when the resolution key is a package path" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "^6.0.0" },
                "resolutions": { "**/is-number": "6.0.0" }
              }
            JSON
          end
          let(:previous_requirement) { "^6.0.0" }
          let(:new_requirement) { "^7.0.0" }

          it "updates the resolution" do
            expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"').sub('"6.0.0"', '"7.0.0"'))
          end
        end

        context "when a nested overrides object declares the same requirement" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "is-number": "^6.0.0" },
                "config": { "overrides": { "is-number": "6.0.0" } },
                "resolutions": { "is-number": "6.0.0" }
              }
            JSON
          end
          let(:previous_requirement) { "^6.0.0" }
          let(:new_requirement) { "^7.0.0" }

          it "updates only the resolution" do
            expect(updated_content).to eq(
              content.sub('"^6.0.0"', '"^7.0.0"')
                     .sub('"resolutions": { "is-number": "6.0.0" }', '"resolutions": { "is-number": "7.0.0" }')
            )
          end
        end
      end

      context "with overrides for a sub-dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "7.0.0",
            previous_version: "6.0.0",
            package_manager: "npm_and_yarn",
            requirements: [],
            previous_requirements: []
          )
        end

        context "when unrelated resolutions precede the overrides" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "left-pad": "^1.3.0" },
                "resolutions": { "etag": "1.0.1" },
                "overrides": { "is-number": "^6.0.0" }
              }
            JSON
          end

          it "updates the override" do
            expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"'))
          end
        end

        context "when the override key is a package path" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "left-pad": "^1.3.0" },
                "resolutions": { "**/is-number": "^6.0.0" }
              }
            JSON
          end

          it "updates the resolution" do
            expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"'))
          end
        end

        context "when a nested overrides object declares the same requirement" do
          let(:content) do
            <<~JSON
              {
                "dependencies": { "left-pad": "^1.3.0" },
                "config": {"overrides":{"is-number":"^6.0.0"}},
                "overrides": { "is-number": "^6.0.0" }
              }
            JSON
          end

          it "updates only the top-level override" do
            expect(updated_content).to eq(content.sub('"is-number": "^6.0.0"', '"is-number": "^7.0.0"'))
          end
        end
      end
    end
  end
end
