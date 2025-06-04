# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "when dealing with yarn lockfiles" do
      let(:dependency_files) { project_dependency_files("yarn/only_dev_dependencies") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "when there is an empty version string" do
        let(:dependency_files) { project_dependency_files("yarn/empty_version") }

        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "when there is an aliased dependency" do
        let(:dependency_files) { project_dependency_files("yarn/aliased_dependency") }

        it "excludes the dependency" do
          # Lockfile contains 11 dependencies but one is an alias
          expect(dependencies.count).to eq(10)
          expect(dependencies.map(&:name)).not_to include("my-fetch-factory")
        end
      end

      context "when there are multiple dependencies" do
        let(:dependency_files) { project_dependency_files("yarn/no_lockfile_change") }

        its(:length) { is_expected.to eq(393) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "acorn" } }

          its(:version) { is_expected.to eq("5.1.1") }
        end
      end

      context "when there are dependencies with multiple requirements" do
        let(:dependency_files) { project_dependency_files("yarn_berry/multiple_requirements") }

        its(:length) { is_expected.to eq(172) }

        it "includes those dependencies" do
          expect(dependencies.map(&:name)).to include("@nodelib/fs.stat")
        end
      end

      context "when there is a bad lockfile" do
        let(:dependency_files) { project_dependency_files("yarn/broken_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("yarn.lock")
            end
        end
      end

      context "when there is an out of disk/memory error" do
        let(:dependency_files) { project_dependency_files("yarn/broken_lockfile") }

        context "when ran out of disk space" do
          before do
            allow(Dependabot::SharedHelpers)
              .to receive(:run_helper_subprocess)
              .and_raise(
                Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                  message: "No space left on device",
                  error_context: {}
                )
              )
          end

          it "raises a helpful error" do
            expect { dependencies }
              .to raise_error(Dependabot::OutOfDisk)
          end
        end

        context "when ran out of memory" do
          before do
            allow(Dependabot::SharedHelpers)
              .to receive(:run_helper_subprocess)
              .and_raise(
                Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                  message: "MemoryError",
                  error_context: {}
                )
              )
          end

          it "raises a helpful error" do
            expect { dependencies }
              .to raise_error(Dependabot::OutOfMemory)
          end
        end
      end
    end

    context "when dealing with pnpm lockfiles" do
      let(:dependency_files) { project_dependency_files("pnpm/only_dev_dependencies") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      # Should have the version in the lock file
      context "when there are dependencies with empty version" do
        let(:dependency_files) { project_dependency_files("pnpm/empty_version") }

        it "generates updated lockfile which excludes empty version dependencies." do
          # excluding empty version
          expect(dependencies.count).to eq(9)
          expect(dependencies.map(&:name)).not_to include("encoding")
        end
      end

      context "when there is an aliased dependency" do
        let(:dependency_files) { project_dependency_files("pnpm/aliased_dependency") }

        it "excludes the dependency" do
          # Lockfile contains 11 dependencies but one is an alias
          expect(dependencies.count).to eq(10)
          expect(dependencies.map(&:name)).not_to include("my-fetch-factory")
        end
      end

      context "when there are multiple dependencies" do
        let(:dependency_files) { project_dependency_files("pnpm/no_lockfile_change") }

        its(:length) { is_expected.to eq(370) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "async" } }

          its(:version) { is_expected.to eq("1.5.2") }
        end
      end

      context "when locked to versions with peer disambiguation suffix" do
        let(:dependency_files) { project_dependency_files("pnpm/peer_disambiguation") }

        its(:length) { is_expected.to eq(121) }

        it "includes those dependencies" do
          expect(dependencies.map(&:name)).to include("@typescript-eslint/parser")
        end
      end

      context "when there is a bad lockfile" do
        let(:dependency_files) { project_dependency_files("pnpm/broken_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("pnpm-lock.yaml")
            end
        end
      end

      context "when dealing with v6.1 format" do
        let(:dependency_files) { project_dependency_files("pnpm/6_1_format") }

        it "parses dependencies properly" do
          expect(dependencies.map(&:name)).to include("@sentry/react")
        end
      end

      context "when dealing with v9.0 format" do
        let(:dependency_files) { project_dependency_files("pnpm/9_0_format") }

        it "parses dependencies properly" do
          expect(dependencies.map(&:name)).to include("@sentry/node")
        end
      end
    end

    context "when dealing with npm lockfiles" do
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

      context "when there are multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/blank_requirement") }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "when there are dependencies with an empty/no version" do
        let(:dependency_files) { project_dependency_files("npm6/empty_version") }

        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "when there is an invalid version requirement string" do
        subject { dependencies.find { |d| d.name == "etag" } }

        let(:dependency_files) { project_dependency_files("npm6/invalid_version_requirement") }

        it { is_expected.to be_nil }
      end

      context "when there are URL versions (i.e., is from a bad version of npm)" do
        let(:dependency_files) { project_dependency_files("npm6/url_versions") }

        # All but 1 dependency in the lockfile has a URL version
        its(:length) { is_expected.to eq(1) }
      end

      context "when there is a bad json" do
        let(:dependency_files) { project_dependency_files("npm6/broken_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("package-lock.json")
            end
        end
      end

      context "when there is a bundled dependencies" do
        subject { dependencies.find { |d| d.name == "tar" } }

        let(:dependency_files) { project_dependency_files("npm6/bundled_sub_dependency") }

        its(:subdependency_metadata) do
          is_expected.to eq([{ npm_bundled: true }])
        end
      end

      context "when dealing with v3 format" do
        let(:dependency_files) { project_dependency_files("npm8/package-lock-v3") }

        its(:length) { is_expected.to eq(2) }
      end

      context "when dealing with v3 format and nested node_modules dependencies" do
        let(:dependency_files) { project_dependency_files("npm8/nested_node_modules_lockfile_v3") }

        it "does not incorrectly parse dependencies with node_modules/ in their name" do
          bad_names = dependencies.filter_map { |dep| dep.name if dep.name.include?("node_modules/") }

          expect(bad_names).to be_empty
        end
      end
    end

    context "when dealing with npm shrinkwraps" do
      let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_only_dev_dependencies") }

      it "parses the dependencies" do
        expect(dependencies.map(&:name)).to contain_exactly("etag")
      end

      context "when there are multiple dependencies" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_blank_requirement") }

        its(:length) { is_expected.to eq(23) }

        describe "a repeated dependency" do
          subject { dependencies.find { |d| d.name == "lodash" } }

          its(:version) { is_expected.to eq("2.4.1") }
        end
      end

      context "when there is an empty version string" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_empty_version") }

        # Lockfile contains 10 dependencies but one has an empty version
        its(:length) { is_expected.to eq(9) }
      end

      context "when there is a bad json" do
        let(:dependency_files) { project_dependency_files("npm6/shrinkwrap_broken") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("npm-shrinkwrap.json")
            end
        end
      end
    end

    context "when dealing with bun.lock" do
      context "when the lockfile is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to eq("Invalid bun.lock file: malformed JSONC at line 3, column 1")
            end
        end
      end

      context "when the lockfile version is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile_version") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to include("lockfileVersion")
            end
        end
      end

      context "when dealing with v0 format" do
        context "with a simple project" do
          let(:dependency_files) { project_dependency_files("bun/simple_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
              name: "fetch-factory",
              version: "0.0.1"
            )
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.length).to eq(11)
          end
        end

        context "with a simple workspace project" do
          let(:dependency_files) { project_dependency_files("bun/simple_workspace_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.find { |d| d.name == "lodash" }).to have_attributes(
              name: "lodash",
              version: "1.3.1"
            )
            expect(dependencies.find { |d| d.name == "chalk" }).to have_attributes(
              name: "chalk",
              version: "0.3.0"
            )
            expect(dependencies.length).to eq(5)
          end
        end
      end

      context "when dealing with v1 format" do
        let(:dependency_files) { project_dependency_files("bun/simple_v1") }

        it "parses dependencies properly" do
          expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
            name: "fetch-factory",
            version: "0.0.1"
          )
          expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
            name: "etag",
            version: "1.8.1"
          )
          expect(dependencies.length).to eq(17)
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

    context "when dealing with yarn lockfiles" do
      let(:dependency_files) { project_dependency_files("yarn/only_dev_dependencies") }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "resolved" => "https://registry.yarnpkg.com/etag/-/etag-1.8.0.tgz#6f631aef336d6c46362b51764044ce216be3c051",
          "version" => "1.8.0"
        )
      end

      context "when containing duplicate dependencies" do
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

          it { is_expected.to be_nil }
        end
      end

      context "when there are multiple requirements" do
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

    context "when dealing with pnpm lockfiles" do
      let(:dependency_files) { project_dependency_files("pnpm/only_dev_dependencies") }

      it "finds the dependency" do
        expect(lockfile_details).to eq(
          "aliased" => false,
          "dev" => true,
          "name" => "etag",
          "specifiers" => ["^1.0.0"],
          "version" => "1.8.0"
        )
      end

      context "when containing duplicate dependencies" do
        let(:dependency_files) { project_dependency_files("pnpm/no_lockfile_change") }
        let(:dependency_name) { "babel-register" }
        let(:requirement) { "^6.24.1" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "aliased" => false,
            "dev" => true,
            "name" => "babel-register",
            "specifiers" => ["^6.24.1"],
            "version" => "6.24.1"
          )
        end

        context "when the requirement doesn't match" do
          let(:requirement) { "^6.26.0" }

          it { is_expected.to be_nil }
        end
      end

      context "when resolved version has peer disambiguation suffix (lockfileFormat 5.4)" do
        let(:dependency_files) { project_dependency_files("pnpm/peer_disambiguation") }
        let(:dependency_name) { "@typescript-eslint/parser" }
        let(:requirement) { "^5.0.0" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "aliased" => false,
            "dev" => true,
            "name" => "@typescript-eslint/parser",
            "specifiers" => ["^5.0.0"],
            "version" => "5.59.0"
          )
        end
      end

      context "when resolved version has peer disambiguation suffix (lockfileFormat 6.0)" do
        let(:dependency_files) { project_dependency_files("pnpm/peer_disambiguation_v6") }
        let(:dependency_name) { "@typescript-eslint/parser" }
        let(:requirement) { "^5.0.0" }

        it "finds the one matching the requirement" do
          expect(lockfile_details).to eq(
            "aliased" => false,
            "dev" => true,
            "name" => "@typescript-eslint/parser",
            "specifiers" => ["^5.0.0"],
            "version" => "5.59.0"
          )
        end
      end

      context "when tarball urls included" do
        let(:dependency_files) { project_dependency_files("pnpm/tarball_urls") }
        let(:dependency_name) { "babel-core" }
        let(:requirement) { "^6.26.0" }

        it "includes the URL in the details" do
          expect(lockfile_details).to eq(
            "aliased" => false,
            "dev" => true,
            "name" => "babel-core",
            "resolved" => "https://registry.npmjs.org/babel-core/-/babel-core-6.26.3.tgz",
            "specifiers" => ["^6.26.0"],
            "version" => "6.26.3"
          )
        end
      end
    end

    context "when dealing with npm lockfiles" do
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

        context "when lockfile should be used for this manifest" do
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

    context "when dealing with npm shrinkwraps" do
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

    context "when dealing with an npm8 workspace project with a direct dependency" do
      context "when the dependency is installed in the workspace's node_modules" do
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
    end

    context "when dealing with an npm8 workspace project with a direct dependency" do
      context "when the dependency installed in the top-level node_modules" do
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
    end

    context "when dealing with a non-workspace npm 8 lockfile" do
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

    context "when npm8 with a v3 lockfile-version" do
      context "when dealing with workspace project with a direct dependency" do
        context "when the dependency is installed in the workspace's node_modules" do
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
      end

      context "when dealing with workspace project with a direct dependency" do
        context "when the dependency is installed in the top-level node_modules" do
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
      end

      context "when dealing with a non-workspace project" do
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
