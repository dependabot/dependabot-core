# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::LockfileParser do
  before do
    Dependabot::Experiments.register(:yarn_berry, true)
  end

  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "for yarn lockfiles" do
      let(:dependency_files) { project_dependency_files("yarn/only_dev_dependencies") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "that contains an empty version string" do
        let(:dependency_files) { project_dependency_files("yarn/empty_version") }

        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that contains an aliased dependency" do
        let(:dependency_files) { project_dependency_files("yarn/aliased_dependency") }

        it "excludes the dependency" do
          # Lockfile contains 11 dependencies but one is an alias
          expect(dependencies.count).to eq(10)
          expect(dependencies.map(&:name)).to_not include("my-fetch-factory")
        end
      end

      context "that contain multiple dependencies" do
        let(:dependency_files) { project_dependency_files("yarn/no_lockfile_change") }

        its(:length) { is_expected.to eq(393) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "acorn" } }

          its(:version) { is_expected.to eq("5.1.1") }
        end
      end

      context "that contain bad lockfile" do
        let(:dependency_files) { project_dependency_files("yarn/broken_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("yarn.lock")
            end
        end
      end
    end

    context "for npm lockfiles" do
      let(:dependency_files) { project_dependency_files("npm6/multiple_updates") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag", "is-number")
      end

      it "doesn't include subdependency_metadata for unbundled dependencies" do
        dep = dependencies.find { |d| d.name == "etag" }
        expect(dep.subdependency_metadata).to be_nil
      end

      context "with a dev dependency" do
        let(:dependency_files) { project_dependency_files("npm6/only_dev_dependencies") }

        it "includes subdependency_metadata for development dependency" do
          dep = dependencies.find { |d| d.name == "etag" }
          expect(dep.subdependency_metadata).to eq([{ production: false }])
        end
      end

      context "that contain multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/blank_requirement") }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "that contains an empty version string" do
        let(:dependency_files) { project_dependency_files("npm6/empty_version") }
        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that contains an invalid version requirement string" do
        let(:dependency_files) { project_dependency_files("npm6/invalid_version_requirement") }
        subject { dependencies.find { |d| d.name == "etag" } }

        it { is_expected.to eq(nil) }
      end

      context "that has URL versions (i.e., is from a bad version of npm)" do
        let(:dependency_files) { project_dependency_files("npm6/url_versions") }

        # All but 1 dependency in the lockfile has a URL version
        its(:length) { is_expected.to eq(1) }
      end

      context "that contain bad json" do
        let(:dependency_files) { project_dependency_files("npm6/broken_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("package-lock.json")
            end
        end
      end

      context "that contain bundled dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/bundled_sub_dependency") }
        subject { dependencies.find { |d| d.name == "tar" } }

        its(:subdependency_metadata) do
          is_expected.to eq([{ npm_bundled: true }])
        end
      end
    end

    context "for npm shrinkwraps" do
      let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_only_dev_dependencies") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "that contain multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_blank_requirement") }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "that contains an empty version string" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_empty_version") }
        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "that contain bad json" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_broken") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("npm-shrinkwrap.json")
            end
        end
      end
    end
  end

  describe "#lockfile_details" do
    subject(:lockfile_details) do
      lockfile_parser.lockfile_details(
        dependency_name: dependency_name,
        requirement: requirement,
        manifest_name: manifest_name
      )
    end
    let(:dependency_name) { "etag" }
    let(:requirement) { nil }
    let(:manifest_name) { "package.json" }

    context "for yarn lockfiles" do
      let(:dependency_files) { project_dependency_files("yarn/only_dev_dependencies") }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "resolved" => "https://registry.yarnpkg.com/etag/-/etag-1.8.0.tgz#6f631aef336d6c46362b51764044ce216be3c051",
          "version" => "1.8.0"
        )
      end

      context "that contain duplicate dependencies" do
        let(:dependency_files) { project_dependency_files("yarn/no_lockfile_change") }
        let(:dependency_name) { "ansi-styles" }
        let(:requirement) { "^2.2.1" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "version" => "2.2.1",
            "resolved" => "https://registry.yarnpkg.com/ansi-styles/-/" \
                          "ansi-styles-2.2.1.tgz#" \
                          "b432dd3358b634cf75e1e4664368240533c1ddbe"
          )
        end

        context "when the requirement doesn't match" do
          let(:requirement) { "^3.3.0" }

          it { is_expected.to eq(nil) }
        end
      end

      context "that have multiple requirements" do
        let(:dependency_files) { project_dependency_files("yarn_berry/multiple_requirements") }
        let(:dependency_name) { "postcss" }
        let(:requirement) { "^8.4.17" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "version" => "8.4.17",
            "resolution" => "postcss@npm:8.4.17",
            "dependencies" => { "nanoid" => "^3.3.4", "picocolors" => "^1.0.0", "source-map-js" => "^1.0.2" },
            "checksum" => "a6d9096dd711e17f7b1d18ff5dcb4fdedf3941d5a3dc8b0e4ea" \
                          "873b8f31972d57f73d6da9a8aed7ff389eb52190ed34f6a94f299a7f5ddc68b08a24a48f77eb9",
            "languageName" => "node",
            "linkType" => "hard"
          )
        end
      end
    end

    context "for npm lockfiles" do
      let(:dependency_files) { project_dependency_files("npm6/only_dev_dependencies") }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "version" => "1.8.1",
          "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
          "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
          "dev" => true
        )
      end

      context "when a nested lockfile is also present" do
        let(:dependency_files) { project_dependency_files("npm6/irrelevant_nested_lockfile") }

        it "finds the correct dependency" do
          expect(lockfile_details).to eq(
            "version" => "1.8.1",
            "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
            "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
            "dev" => true
          )
        end

        context "that should be used for this manifest" do
          let(:manifest_name) { "nested/package.json" }

          it "finds the correct dependency" do
            expect(lockfile_details).to eq(
              "version" => "1.8.0",
              "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.0.tgz",
              "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSm111c="
            )
          end
        end
      end
    end

    context "for npm shrinkwraps" do
      let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_only_dev_dependencies") }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "version" => "1.8.1",
          "resolved" => "https://registry.npmjs.org/etag/-/etag-1.8.1.tgz",
          "integrity" => "sha1-Qa4u62XvpiJorr/qg6x9eSmbCIc=",
          "dev" => true
        )
      end
    end

    context "for an npm8 workspace project with a direct dependency that's installed in the workspace's node_modules" do
      let(:dependency_files) { project_dependency_files("npm8/workspace_nested_package") }
      let(:dependency_name) { "yargs" }
      let(:manifest_name) { "packages/build/package.json" }

      it "finds the correct dependency" do
        expect(lockfile_details).to eq(
          "version" => "16.2.0",
          "resolved" => "https://registry.npmjs.org/yargs/-/yargs-16.2.0.tgz",
          "integrity" =>
            "sha512-D1mvvtDG0L5ft/jGWkLpG1+m0eQxOfaBvTNELraWj22wSVUMWxZUvYgJYcKh6jGGIkJFhH4IZPQhR4TKpc8mBw=="
        )
      end
    end

    context "for an npm8 workspace project with a direct dependency that's installed in the top-level node_modules" do
      let(:dependency_files) { project_dependency_files("npm8/workspace_nested_package_top_level") }
      let(:dependency_name) { "uuid" }
      let(:manifest_name) { "api/package.json" }

      it "finds the correct dependency" do
        expect(lockfile_details).to eq(
          "version" => "8.3.2",
          "resolved" => "https://registry.npmjs.org/uuid/-/uuid-8.3.2.tgz",
          "integrity" =>
            "sha512-+NYs2QeMWy+GWFOEm9xnn6HCDp0l7QBD7ml8zLUmJ+93Q5NF0NocErnwkTkXVFNiX3/fpC6afS8Dhb/gz7R7eg=="
        )
      end
    end

    context "for a non-workspace npm 8 lockfile" do
      let(:dependency_files) { project_dependency_files("npm8/simple") }
      let(:dependency_name) { "fetch-factory" }
      let(:manifest_name) { "package.json" }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "version" => "0.0.1",
          "resolved" => "https://registry.npmjs.org/fetch-factory/-/fetch-factory-0.0.1.tgz",
          "integrity" => "sha1-4AdgWb2zHjFHx1s7jAQTO6jH4HE="
        )
      end
    end

    context "npm8 with a v3 lockfile-version" do
      context "workspace project with a direct dependency that's installed in the workspace's node_modules" do
        let(:dependency_files) { project_dependency_files("npm8/workspace_nested_package_lockfile_v3") }
        let(:dependency_name) { "yargs" }
        let(:manifest_name) { "packages/build/package.json" }

        it "finds the correct dependency" do
          expect(lockfile_details).to eq(
            "version" => "16.2.0",
            "resolved" => "https://registry.npmjs.org/yargs/-/yargs-16.2.0.tgz",
            "integrity" =>
            "sha512-D1mvvtDG0L5ft/jGWkLpG1+m0eQxOfaBvTNELraWj22wSVUMWxZUvYgJYcKh6jGGIkJFhH4IZPQhR4TKpc8mBw=="
          )
        end
      end

      context "workspace project with a direct dependency that's installed in the top-level node_modules" do
        let(:dependency_files) { project_dependency_files("npm8/workspace_nested_package_top_level_lockfile_v3") }
        let(:dependency_name) { "uuid" }
        let(:manifest_name) { "api/package.json" }

        it "finds the correct dependency" do
          expect(lockfile_details).to eq(
            "version" => "8.3.2",
            "resolved" => "https://registry.npmjs.org/uuid/-/uuid-8.3.2.tgz",
            "integrity" =>
            "sha512-+NYs2QeMWy+GWFOEm9xnn6HCDp0l7QBD7ml8zLUmJ+93Q5NF0NocErnwkTkXVFNiX3/fpC6afS8Dhb/gz7R7eg=="
          )
        end
      end

      context "for a non-workspace project" do
        let(:dependency_files) { project_dependency_files("npm8/simple_lockfile_v3") }
        let(:dependency_name) { "fetch-factory" }
        let(:manifest_name) { "package.json" }

        it "finds the dependency" do
          expect(lockfile_details).to eq(
            "version" => "0.0.1",
            "resolved" => "https://registry.npmjs.org/fetch-factory/-/fetch-factory-0.0.1.tgz",
            "integrity" => "sha1-4AdgWb2zHjFHx1s7jAQTO6jH4HE="
          )
        end
      end
    end
  end
end
