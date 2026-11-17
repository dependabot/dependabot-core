# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only content fixture used by the parent package_json fixture.

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/file_updater/package_json_updater"

RSpec.describe Dependabot::Bun::FileUpdater::PackageJsonUpdater do
  extend T::Sig

  describe "#updated_package_json" do
    subject(:updated_content) do
      described_class.new(package_json: package_json, dependencies: [dependency]).updated_package_json.content
    end

    let(:package_json) { Dependabot::DependencyFile.new(name: "package.json", content: content) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: version,
        previous_version: previous_version,
        package_manager: "bun",
        requirements: [catalog_requirement(requirement)],
        previous_requirements: [catalog_requirement(previous_requirement)]
      )
    end
    let(:dependency_name) { "is-number" }
    let(:catalog) { "default" }
    let(:previous_version) { "6.0.0" }
    let(:version) { "7.0.0" }
    let(:previous_requirement) { "^6.0.0" }
    let(:requirement) { "^7.0.0" }
    let(:source) { nil }

    sig { params(requirement: T.nilable(String)).returns(T::Hash[Symbol, T.anything]) }
    def catalog_requirement(requirement)
      { file: "package.json", requirement: requirement, groups: ["dependencies"], source: source,
        metadata: { catalog: catalog } }
    end

    context "when a compact ignored root catalog precedes the workspaces catalog" do
      let(:content) do
        <<~JSON
          {
            "catalog": {"is-number":"^6.0.0"},
            "workspaces": {
              "packages": ["packages/*"],
              "catalog": { "is-number": "^6.0.0" }
            }
          }
        JSON
      end

      it "updates only the workspaces catalog" do
        expect(updated_content).to eq(content.sub('"is-number": "^6.0.0"', '"is-number": "^7.0.0"'))
      end
    end

    context "when the workspaces catalog is compact and the ignored root catalog is not" do
      let(:content) do
        <<~JSON
          {
            "catalog": { "is-number": "^6.0.0" },
            "workspaces": {"packages":["packages/*"],"catalog":{"is-number":"^6.0.0"}}
          }
        JSON
      end

      it "updates only the workspaces catalog" do
        expect(updated_content).to eq(content.sub('{"is-number":"^6.0.0"}', '{"is-number":"^7.0.0"}'))
      end
    end

    context "when another section declares the same requirement first with different formatting" do
      let(:content) do
        <<~JSON
          {
            "devDependencies": {"is-number":"^6.0.0"},
            "workspaces": ["packages/*"],
            "catalog": {
              "is-number": "^6.0.0"
            }
          }
        JSON
      end

      it "updates only the catalog entry" do
        expect(updated_content).to eq(content.sub('"is-number": "^6.0.0"', '"is-number": "^7.0.0"'))
      end
    end

    context "with extra spaces around the separator" do
      let(:content) do
        <<~JSON
          {
            "workspaces": ["packages/*"],
            "catalog": {
              "is-number"   :     "^6.0.0"
            }
          }
        JSON
      end

      it "keeps the spacing" do
        expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"'))
      end
    end

    context "with several entries on one line" do
      let(:content) do
        <<~JSON
          {
            "workspaces": ["packages/*"],
            "catalog": { "is-odd": "^6.0.0", "is-number": "^6.0.0", "is-even": "^6.0.0" }
          }
        JSON
      end

      it "updates only the dependency's entry" do
        expect(updated_content).to eq(content.sub('"is-number": "^6.0.0"', '"is-number": "^7.0.0"'))
      end
    end

    context "with a minified document and an ignored root catalog after the workspaces catalog" do
      let(:dependency_name) { "etag" }
      let(:catalog) { "testing" }
      let(:previous_version) { "1.0.1" }
      let(:version) { "1.8.1" }
      let(:previous_requirement) { "1.0.1" }
      let(:requirement) { "1.8.1" }
      let(:content) do
        '{"workspaces":{"catalogs":{"testing":{"etag":"1.0.1"}},"packages":["packages/*"]},' \
          '"catalogs":{"testing":{"etag":"1.0.1"}}}'
      end

      it "updates only the workspaces catalog" do
        expect(updated_content).to eq(content.sub('"etag":"1.0.1"', '"etag":"1.8.1"'))
      end
    end

    context "with catalogs declared before catalog and non-ASCII text before both" do
      let(:content) do
        <<~JSON
          {
            "description": "Shared catalogs — ☕",
            "workspaces": {
              "catalogs": { "default": { "is-odd": "^6.0.0" } },
              "catalog": { "is-number": "^6.0.0" },
              "packages": ["packages/*"]
            }
          }
        JSON
      end

      it "updates the default catalog entry" do
        expect(updated_content).to eq(content.sub('"is-number": "^6.0.0"', '"is-number": "^7.0.0"'))
      end
    end

    context "with a key written with an escape sequence" do
      let(:content) do
        <<~JSON
          {
            "workspaces": ["packages/*"],
            "catalog": { "is-\\u006eumber": "^6.0.0" }
          }
        JSON
      end

      it "updates the entry" do
        expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"'))
      end
    end

    context "with a compact git catalog entry" do
      let(:dependency_name) { "is-number" }
      let(:previous_version) { "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      let(:version) { "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
      let(:previous_requirement) { nil }
      let(:requirement) { nil }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          previous_version: previous_version,
          package_manager: "bun",
          requirements: [catalog_requirement(nil).merge(source: git_source("v7.0.0"))],
          previous_requirements: [catalog_requirement(nil).merge(source: git_source("v6.0.0"))]
        )
      end
      let(:content) do
        <<~JSON
          {
            "workspaces": ["packages/*"],
            "catalog": {"is-number":"github:jonschlinkert/is-number#v6.0.0"}
          }
        JSON
      end

      sig { params(ref: String).returns(T::Hash[Symbol, T.nilable(String)]) }
      def git_source(ref)
        { type: "git", url: "https://github.com/jonschlinkert/is-number", branch: nil, ref: ref }
      end

      it "updates the ref" do
        expect(updated_content).to eq(content.sub("#v6.0.0", "#v7.0.0"))
      end

      context "when the update moves it to the registry" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "7.0.0",
            previous_version: previous_version,
            package_manager: "bun",
            requirements: [catalog_requirement("^7.0.0")],
            previous_requirements: [catalog_requirement(nil).merge(source: git_source("v6.0.0"))]
          )
        end

        it "replaces the git URL with the requirement" do
          expect(updated_content).to eq(content.sub("github:jonschlinkert/is-number#v6.0.0", "^7.0.0"))
        end
      end
    end
  end
end
