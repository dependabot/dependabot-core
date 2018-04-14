# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/java_script/npm_and_yarn/package_json_updater"

namespace = Dependabot::FileUpdaters::JavaScript::NpmAndYarn
RSpec.describe namespace::PackageJsonUpdater do
  let(:package_json_updater) do
    described_class.new(
      package_json: package_json,
      dependencies: dependencies
    )
  end

  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: fixture("javascript", "package_files", manifest_fixture_name),
      name: "package.json"
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:dependencies) { [dependency] }
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

  describe "#updated_package_json" do
    subject(:updated_package_json) { package_json_updater.updated_package_json }

    its(:content) { is_expected.to include "{{ name }}" }
    its(:content) { is_expected.to include "\"fetch-factory\": \"^0.0.2\"" }
    its(:content) { is_expected.to include "\"etag\" : \"^1.0.0\"" }

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
        parsed_file = JSON.parse(updated_package_json.content)
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
        parsed_file = JSON.parse(updated_package_json.content)
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
          parsed_file = JSON.parse(updated_package_json.content)
          expect(parsed_file.dig("dependencies", "fetch-factory")).
            to eq("^0.2.0")
          expect(parsed_file.dig("devDependencies", "fetch-factory")).
            to eq("^0.2.0")
        end
      end
    end

    context "with a path-based dependency" do
      let(:manifest_fixture_name) { "path_dependency.json" }
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

    context "with non-standard whitespace" do
      let(:manifest_fixture_name) { "non_standard_whitespace.json" }

      its(:content) do
        is_expected.to include %("*.js": ["eslint --fix", "git add"])
      end
    end
  end
end
