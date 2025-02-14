# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::NpmAndYarn::FileParser do
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      credentials: credentials
    )
  end

  # Variable to control the npm fallback version feature flag
  let(:npm_fallback_version_above_v6_enabled) { true }

  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_fallback_version_above_v6).and_return(npm_fallback_version_above_v6_enabled)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_v6_deprecation_warning).and_return(true)
  end

  after do
    Dependabot::Experiments.reset!
  end

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    describe "top level dependencies" do
      subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

      context "with no lockfile" do
        let(:npm_fallback_version_above_v6_enabled) { false }

        let(:files) { project_dependency_files("npm6/exact_version_requirements_no_lockfile") }

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency" do
          subject { top_level_dependencies.first }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("chalk") }
          its(:version) { is_expected.to eq("0.3.0") }
        end
      end

      context "with no lockfile, and non exact requirements" do
        let(:files) { project_dependency_files("generic/file_version_requirements_no_lockfile") }

        its(:length) { is_expected.to eq(0) }
      end

      context "with yarn `workspace:` requirements and no lockfile" do
        let(:files) { project_dependency_files("yarn/workspace_requirements_no_lockfile") }

        its(:length) { is_expected.to eq(0) }
      end

      context "with pnpm `catalog:` requirements and no lockfile" do
        let(:files) { project_dependency_files("pnpm/workspace_requirements_catalog") }

        its(:length) { is_expected.to eq(0) }
      end

      context "with a package-lock.json" do
        let(:npm_fallback_version_above_v6_enabled) { false }

        let(:files) { project_dependency_files("npm6/simple") }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end
          end
        end

        context "with a blank requirement" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/blank_requirement") }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.2.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "*",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end
          end
        end

        context "with an ignored hash requirement" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/hash_requirement") }

          its(:length) { is_expected.to eq(2) }
        end

        context "when containing an empty version string for a sub-dep" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/empty_version") }

          its(:length) { is_expected.to eq(2) }
        end

        context "when containing a version requirement string" do
          subject { dependencies.find { |d| d.name == "etag" } }

          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/invalid_version_requirement") }

          it { is_expected.to be_nil }
        end

        context "when containing URL versions (i.e., is from a bad version of npm)" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/url_versions") }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("hashids") }
            its(:version) { is_expected.to eq("1.1.4") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.1.4",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end
          end
        end

        context "with only dev dependencies" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/only_dev_dependencies") }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end
          end
        end

        context "when the dependency is specified as both dev and runtime" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/duplicate") }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to be_nil }

            its(:requirements) do
              is_expected.to eq(
                [{
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
          end
        end

        context "with a private-source dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/private_source") }

          its(:length) { is_expected.to eq(7) }

          describe "the first private dependency" do
            subject { top_level_dependencies[1] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("chalk") }
            its(:version) { is_expected.to eq("2.3.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "registry",
                    url: "http://registry.npm.taobao.org"
                  }
                }]
              )
            end
          end

          describe "the gemfury dependency" do
            subject { top_level_dependencies[2] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/etag") }
            its(:version) { is_expected.to eq("1.8.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://npm.fury.io/dependabot"
                  }
                }]
              )
            end
          end

          describe "the GPR dependency" do
            subject { top_level_dependencies[5] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-3") }
            its(:version) { is_expected.to eq("2.0.14") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://npm.pkg.github.com"
                  }
                }]
              )
            end

            context "with a credential that matches the hostname, but not the path" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" => "npm.pkg.github.com/dependabot",
                  "username" => "x-access-token",
                  "password" => "token"
                })]
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^2.0.1",
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "registry",
                      url: "https://npm.pkg.github.com"
                    }
                  }]
                )
              end
            end
          end

          describe "the scoped gitlab dependency" do
            subject { top_level_dependencies[6] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-4") }
            its(:version) { is_expected.to eq("2.0.14") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://gitlab.mydomain.com/api/v4/" \
                         "packages/npm"
                  }
                }]
              )
            end
          end

          describe "the scoped artifactory dependency" do
            subject { top_level_dependencies[3] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core") }
            its(:version) { is_expected.to eq("2.0.14") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://artifactory01.mydomain.com/artifactory/api/" \
                         "npm/my-repo"
                  }
                }]
              )
            end
          end

          describe "the unscoped artifactory dependency" do
            subject { top_level_dependencies[0] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "registry",
                    url: "https://artifactory01.mydomain.com/artifactory/api/" \
                         "npm/my-repo"
                  }
                }]
              )
            end

            context "with credentials" do
              let(:credentials) do
                [Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" =>
                     "artifactory01.mydomain.com.evil.com/artifactory/api/npm/my-repo",
                  "token" => "secret_token"
                }), Dependabot::Credential.new({
                  "type" => "npm_registry",
                  "registry" =>
                    "artifactory01.mydomain.com/artifactory/api/npm/my-repo",
                  "token" => "secret_token"
                })]
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^0.0.1",
                    file: "package.json",
                    groups: ["dependencies"],
                    source: {
                      type: "registry",
                      url: "https://artifactory01.mydomain.com/artifactory/" \
                           "api/npm/my-repo"
                    }
                  }]
                )
              end

              context "when excluding the auth token" do
                let(:credentials) do
                  [Dependabot::Credential.new({
                    "type" => "npm_registry",
                    "registry" =>
                      "artifactory01.mydomain.com/artifactory/api/npm/my-repo"
                  })]
                end

                its(:requirements) do
                  is_expected.to eq(
                    [{
                      requirement: "^0.0.1",
                      file: "package.json",
                      groups: ["dependencies"],
                      source: {
                        type: "registry",
                        url: "https://artifactory01.mydomain.com/artifactory/" \
                             "api/npm/my-repo"
                      }
                    }]
                  )
                end
              end
            end
          end

          describe "the bintray dependency" do
            subject { top_level_dependencies[4] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-2") }
            its(:version) { is_expected.to eq("2.0.14") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://api.bintray.com/npm/dependabot/npm-private"
                  }
                }]
              )
            end
          end
        end

        context "with an optional dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/optional_dependencies") }

          its(:length) { is_expected.to eq(2) }

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["optionalDependencies"],
                  source: { type: "registry", url: "https://registry.npmjs.org" }
                }]
              )
            end
          end
        end

        context "with a path-based dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) do
            project_dependency_files("npm6/path_dependency").tap do |files|
              file = files.find { |f| f.name == "deps/etag/package.json" }
              file.support_file = true
            end
          end

          it "doesn't include the path-based dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).not_to include("etag")
          end
        end

        context "with a git-url dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/git_dependency") }

          its(:length) { is_expected.to eq(4) }

          describe "the git dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }

            its(:version) do
              is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
            end

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number.git",
                    branch: nil,
                    ref: "master"
                  }
                }]
              )
            end

            context "when the lockfile has a branch for the version" do
              let(:npm_fallback_version_above_v6_enabled) { false }

              let(:files) { project_dependency_files("npm6/git_dependency_branch_version") }

              it "is excluded" do
                expect(top_level_dependencies.map(&:name))
                  .not_to include("is-number")
              end
            end
          end
        end

        context "with a github dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6/github_dependency") }

          its(:length) { is_expected.to eq(1) }

          describe "the github dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }

            its(:version) do
              is_expected.to eq("d5ac0584ee9ae7bd9288220a39780f155b9ad4c8")
            end

            its(:requirements) do
              is_expected.to eq(
                [{
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
          end

          context "when specifying a semver requirement" do
            let(:npm_fallback_version_above_v6_enabled) { false }

            let(:files) { project_dependency_files("npm6/github_dependency_semver") }
            let(:git_pack_fixture_name) { "is-number" }

            before do
              git_url = "https://github.com/jonschlinkert/is-number.git"
              git_header = {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
              pack_url = git_url + "/info/refs?service=git-upload-pack"
              stub_request(:get, pack_url)
                .with(basic_auth: %w(x-access-token token))
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", git_pack_fixture_name),
                  headers: git_header
                )
            end

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to eq("2.0.2") }

              its(:requirements) do
                is_expected.to eq(
                  [{
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

              context "when a tag can't be found" do
                let(:git_pack_fixture_name) { "manifesto" }

                its(:version) do
                  is_expected.to eq("63d5b26c793194bf7f341a7203e0e5568c753539")
                end
              end

              context "when the git repo can't be found" do
                before do
                  git_url = "https://github.com/jonschlinkert/is-number.git"
                  pack_url = git_url + "/info/refs?service=git-upload-pack"
                  stub_request(:get, pack_url)
                    .with(basic_auth: %w(x-access-token token))
                    .to_return(status: 404)
                end

                its(:version) do
                  is_expected.to eq("63d5b26c793194bf7f341a7203e0e5568c753539")
                end
              end
            end
          end

          context "when not specifying a reference" do
            let(:npm_fallback_version_above_v6_enabled) { false }

            let(:files) { project_dependency_files("npm6/github_dependency_no_ref") }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }

              its(:version) do
                is_expected.to eq("d5ac0584ee9ae7bd9288220a39780f155b9ad4c8")
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
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
            end
          end

          context "when specifying with its shortname" do
            let(:npm_fallback_version_above_v6_enabled) { false }

            let(:files) { project_dependency_files("npm6/github_shortname") }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }

              its(:version) do
                is_expected.to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
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
            end
          end
        end

        context "with only a package.json" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:project_name) { "npm6/simple" }
          let(:files) { project_dependency_files(project_name).select { |f| f.name == "package.json" } }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to be_nil }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "with a git dependency" do
            let(:npm_fallback_version_above_v6_enabled) { false }

            let(:project_name) { "npm6/git_dependency" }

            its(:length) { is_expected.to eq(4) }

            describe "the git dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to be_nil }

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end

            context "when the dependency also has a non-git source" do
              let(:npm_fallback_version_above_v6_enabled) { false }

              let(:project_name) { "npm6/multiple_sources" }

              it "excludes the dependency" do
                expect(dependencies.map(&:name)).to eq(["fetch-factory"])
              end
            end
          end

          context "when it does flat resolution" do
            let(:npm_fallback_version_above_v6_enabled) { false }

            let(:project_name) { "npm6/flat_resolution" }

            its(:length) { is_expected.to eq(0) }
          end
        end
      end

      context "with an npm-shrinkwrap.json" do
        let(:files) { project_dependency_files("npm4/shrinkwrap") }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "when it has relative resolved paths" do
          let(:files) { project_dependency_files("npm4/shrinkwrap_relative") }

          its(:length) { is_expected.to eq(2) }

          context "with a version specified" do
            describe "the first dependency" do
              subject { top_level_dependencies.first }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("fetch-factory") }
              its(:version) { is_expected.to eq("0.0.1") }

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^0.0.1",
                    file: "package.json",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end
          end
        end
      end

      context "with a yarn.lock" do
        let(:files) { project_dependency_files("yarn/simple") }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              )
            end
          end
        end

        context "when a dist-tag is specified" do
          let(:files) { project_dependency_files("yarn/dist_tag") }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("npm") }
            its(:version) { is_expected.to eq("5.8.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "next",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              )
            end
          end
        end

        context "with only dev dependencies" do
          let(:files) { project_dependency_files("yarn/only_dev_dependencies") }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              )
            end
          end
        end

        context "with an optional dependency" do
          let(:files) { project_dependency_files("yarn/optional_dependencies") }

          its(:length) { is_expected.to eq(2) }

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.7.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["optionalDependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              )
            end
          end
        end

        context "with a resolution" do
          let(:files) { project_dependency_files("yarn/resolutions") }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            # Resolutions affect sub-dependencies, *not* top-level dependencies.
            # The parsed version should therefore be 0.1.0, *not* 1.0.0.
            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("lodash")
              expect(dependency.version).to eq("0.1.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "^0.1.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: { type: "registry", url: "https://registry.yarnpkg.com" }
                }]
              )
            end
          end
        end

        context "when it specifies a semver requirement" do
          let(:files) { project_dependency_files("yarn/github_dependency_yarn_semver") }

          its(:length) { is_expected.to eq(1) }

          describe "the github dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }
            its(:version) { is_expected.to eq("2.0.2") }

            its(:requirements) do
              is_expected.to eq(
                [{
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
          end

          context "with #semver:" do
            let(:files) { project_dependency_files("yarn/github_dependency_semver") }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to eq("2.0.2") }

              its(:requirements) do
                is_expected.to eq(
                  [{
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
            end
          end
        end

        context "with a private-source dependency" do
          let(:files) { project_dependency_files("yarn/private_source") }

          its(:length) { is_expected.to eq(7) }

          describe "the second dependency" do
            subject { top_level_dependencies[1] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("chalk") }
            its(:version) { is_expected.to eq("2.3.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "registry",
                    url: "http://registry.npm.taobao.org"
                  }
                }]
              )
            end
          end

          describe "the third dependency" do
            subject { top_level_dependencies[2] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/etag") }
            its(:version) { is_expected.to eq("1.8.0") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "registry",
                    url: "https://npm.fury.io/dependabot"
                  }
                }]
              )
            end
          end
        end

        context "with a path-based dependency" do
          let(:files) do
            project_dependency_files("yarn/path_dependency").tap do |files|
              file = files.find { |f| f.name == "deps/etag/package.json" }
              file.support_file = true
            end
          end

          it "doesn't include the path-based dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).not_to include("etag")
          end
        end

        context "with a submodule dependency" do
          let(:files) do
            project_dependency_files("yarn/submodule_dependency").tap do |files|
              file = files.find { |f| f.name == "yarn-workspace-git-submodule-example/package.json" }
              file.support_file = true
            end
          end

          it "doesn't include the submodule dependency" do
            expect(dependencies.map(&:name)).not_to include("pino-pretty")
          end
        end

        context "with a symlinked dependency" do
          let(:files) { project_dependency_files("yarn/symlinked_dependency") }

          it "doesn't include the link dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).not_to include("etag")
          end
        end

        context "with an aliased dependency" do
          let(:files) { project_dependency_files("yarn/aliased_dependency") }

          it "doesn't include the aliased dependency" do
            expect(top_level_dependencies.length).to eq(1)
            expect(top_level_dependencies.map(&:name)).to eq(["etag"])
            expect(dependencies.map(&:name)).not_to include("my-fetch-factory")
          end
        end

        context "with an aliased dependency name (only supported by yarn)" do
          let(:files) { project_dependency_files("yarn/aliased_dependency_name") }

          it "doesn't include the aliased dependency" do
            expect(top_level_dependencies.length).to eq(1)
            expect(top_level_dependencies.map(&:name)).to eq(["etag"])
            expect(dependencies.map(&:name)).not_to include("my-fetch-factory")
          end
        end

        context "with a git dependency" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6_and_yarn/git_dependency") }

          its(:length) { is_expected.to eq(4) }

          describe "the git dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }

            its(:version) do
              is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
            end

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number.git",
                    branch: nil,
                    ref: "master"
                  }
                }]
              )
            end

            context "when the lockfile entry's requirement is outdated" do
              let(:files) { project_dependency_files("yarn/git_dependency_outdated_req") }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }

              its(:version) do
                is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end
          end

          context "with a github dependency" do
            let(:files) { project_dependency_files("yarn/github_dependency_slash") }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("bull-arena") }

              its(:version) do
                is_expected.to eq("717ae633af6429206bdc57ce994ce7e45ac48a8e")
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["dependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/bee-queue/arena",
                      branch: nil,
                      ref: "717ae633af6429206bdc57ce994ce7e45ac48a8e"
                    }
                  }]
                )
              end
            end
          end

          context "with auth details" do
            let(:files) { project_dependency_files("yarn/git_dependency_with_auth") }

            describe "the git dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }

              its(:version) do
                is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://username:password@github.com/" \
                           "jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end

            context "when specified with https and a colon (supported by npm)" do
              let(:npm_fallback_version_above_v6_enabled) { false }

              let(:files) { project_dependency_files("npm6/git_dependency_with_auth") }

              describe "the git dependency" do
                subject { top_level_dependencies.last }

                its(:requirements) do
                  is_expected.to eq(
                    [{
                      requirement: nil,
                      file: "package.json",
                      groups: ["devDependencies"],
                      source: {
                        type: "git",
                        url: "https://username:password@github.com/" \
                             "jonschlinkert/is-number.git",
                        branch: nil,
                        ref: "master"
                      }
                    }]
                  )
                end
              end
            end
          end
        end

        context "with a git source that comes from a sub-dependency" do
          let(:files) { project_dependency_files("yarn/git_dependency_from_subdep") }

          describe "the chalk dependency" do
            subject { dependencies.find { |d| d.name == "chalk" } }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:version) { is_expected.to eq("2.4.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with workspaces" do
          let(:files) { project_dependency_files("yarn/workspaces") }

          its(:length) { is_expected.to eq(3) }

          describe "the etag dependency" do
            subject { top_level_dependencies.find { |d| d.name == "etag" } }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }

            its(:requirements) do
              is_expected.to contain_exactly({
                requirement: "^1.1.0",
                file: "packages/package1/package.json",
                groups: ["devDependencies"],
                source: { type: "registry", url: "https://registry.yarnpkg.com" }
              }, {
                requirement: "^1.0.0",
                file: "other_package/package.json",
                groups: ["devDependencies"],
                source: { type: "registry", url: "https://registry.yarnpkg.com" }
              })
            end
          end

          describe "the duplicated dependency" do
            subject { top_level_dependencies.find { |d| d.name == "lodash" } }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("lodash") }
            its(:version) { is_expected.to eq("1.2.0") }

            its(:requirements) do
              is_expected.to contain_exactly({
                requirement: "1.2.0",
                file: "package.json",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.yarnpkg.com" }
              }, {
                requirement: "^1.2.1",
                file: "other_package/package.json",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.yarnpkg.com" }
              }, {
                requirement: "^1.2.1",
                file: "packages/package1/package.json",
                groups: ["dependencies"],
                source: { type: "registry", url: "https://registry.yarnpkg.com" }
              })
            end
          end
        end

        context "with lerna.json" do
          let(:npm_fallback_version_above_v6_enabled) { false }

          let(:files) { project_dependency_files("npm6_and_yarn/lerna") }

          its(:length) { is_expected.to eq(5) }

          it "parses the lerna dependency" do
            dependency = top_level_dependencies.find { |d| d.name == "lerna" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("lerna")
            expect(dependency.version).to eq("3.6.0")
            expect(dependency.requirements).to contain_exactly({
              requirement: "^3.6.0",
              file: "package.json",
              groups: ["devDependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            })
          end

          it "parses the etag dependency" do
            dependency = top_level_dependencies.find { |d| d.name == "etag" }
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("etag")
            expect(dependency.version).to eq("1.8.0")
            expect(dependency.requirements).to contain_exactly({
              requirement: "^1.1.0",
              file: "packages/package1/package.json",
              groups: ["devDependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }, {
              requirement: "^1.0.0",
              file: "packages/other_package/package.json",
              groups: ["devDependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            })
          end
        end
      end

      describe "with a yarn Berry compatible lockfile" do
        let(:files) { project_dependency_files("yarn_berry/simple") }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }

            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil # TODO: Determine yarn berry sources, for now assume everything is on npmjs.org
                }]
              )
            end
          end
        end
      end

      context "with workspaces" do
        let(:files) { project_dependency_files("yarn_berry/workspaces") }

        its(:length) { is_expected.to eq(3) }

        describe "the etag dependency" do
          subject { top_level_dependencies.find { |d| d.name == "etag" } }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("etag") }
          its(:version) { is_expected.to eq("1.8.1") }

          its(:requirements) do
            is_expected.to contain_exactly({
              requirement: "^1.1.0",
              file: "packages/package1/package.json",
              groups: ["devDependencies"],
              source: nil # TODO: { type: "registry", url: "https://registry.yarnpkg.com" }
            }, {
              requirement: "^1.0.0",
              file: "other_package/package.json",
              groups: ["devDependencies"],
              source: nil # TODO: { type: "registry", url: "https://registry.yarnpkg.com" }
            })
          end
        end

        describe "the duplicated dependency" do
          subject { top_level_dependencies.find { |d| d.name == "lodash" } }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("lodash") }
          its(:version) { is_expected.to eq("1.2.0") }

          its(:requirements) do
            is_expected.to contain_exactly({
              requirement: "1.2.0",
              file: "package.json",
              groups: ["dependencies"],
              source: nil # TODO: { type: "registry", url: "https://registry.yarnpkg.com" }
            }, {
              requirement: "^1.2.1",
              file: "other_package/package.json",
              groups: ["dependencies"],
              source: nil # TODO: { type: "registry", url: "https://registry.yarnpkg.com" }
            }, {
              requirement: "^1.2.1",
              file: "packages/package1/package.json",
              groups: ["dependencies"],
              source: nil # TODO: { type: "registry", url: "https://registry.yarnpkg.com" }
            })
          end
        end
      end

      context "with pnpm catalog protocol" do
        let(:files) { project_dependency_files("pnpm/catalogs_all_examples") }

        its(:length) { is_expected.to eq(6) }

        it "parses the dependency" do
          expect(top_level_dependencies.map(&:name)).to eq(%w(
            react-icons
            prettier
            express
            is-even
            react
            react-dom
          ))
        end

        it "parses the dependency requirements" do
          expected_dependencies = [
            {
              name: "react-icons",
              version: "4.3.1",
              requirements: [
                { requirement: "4.3.1", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            },
            {
              name: "prettier",
              version: "3.3.0",
              requirements: [
                { requirement: "3.3.0", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            },
            {
              name: "express",
              version: "4.15.2",
              requirements: [
                { requirement: "4.15.2", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            },
            {
              name: "is-even",
              version: "0.1.2",
              requirements: [
                { requirement: "0.1.2", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            },
            {
              name: "react",
              version: "16.0.0",
              requirements: [
                { requirement: "^18.0.0", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil },
                { requirement: "16.0.0", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            },
            {
              name: "react-dom",
              version: "18.0.0",
              requirements: [
                { requirement: "18.0.0", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil },
                { requirement: "^16.2.0", file: "pnpm-workspace.yaml", groups: ["dependencies"], source: nil }
              ]
            }
          ]

          expected_dependencies.each_with_index do |expected, index|
            expect(dependencies[index].name).to eq(expected[:name])
            expect(dependencies[index].version).to eq(expected[:version])
            expect(dependencies[index].requirements).to eq(expected[:requirements])
          end
        end
      end
    end

    describe "sub-dependencies" do
      subject(:subdependencies) { dependencies.reject(&:top_level?) }

      context "with a yarn.lock" do
        let(:files) { project_dependency_files("yarn/no_lockfile_change") }

        its(:length) { is_expected.to eq(389) }
      end

      context "with a pnpm-lock.yaml" do
        let(:files) { project_dependency_files("pnpm/no_lockfile_change") }

        its(:length) { is_expected.to eq(366) }
      end

      context "with a package-lock.json" do
        let(:npm_fallback_version_above_v6_enabled) { false }

        let(:files) { project_dependency_files("npm6/blank_requirement") }

        its(:length) { is_expected.to eq(22) }
      end
    end

    context "with duplicate dependencies" do
      subject(:parsed_file) { parser.parse }

      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm6_and_yarn/duplicate_dependency") }

      it "includes both registries" do
        expect(parsed_file.count).to be(1)
        expect(parsed_file[0].requirements).to contain_exactly({
          requirement: "^10.5.12",
          file: "package.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.yarnpkg.com" }
        }, {
          requirement: "10.5.12",
          file: "package.json",
          groups: ["devDependencies"],
          source: { type: "registry", url: "https://registry.yarnpkg.com" }
        })
      end
    end

    context "with multiple versions of a dependency" do
      subject(:parsed_file) { parser.parse }

      let(:files) { project_dependency_files("npm8/transitive_dependency_multiple_versions") }

      it "stores all versions of the dependency in its metadata" do
        name = "kind-of"
        dependency = parsed_file.find { |dep| dep.name == name }

        expect(dependency.metadata[:all_versions]).to eq([
          Dependabot::Dependency.new(
            name: name,
            version: "3.2.2",
            requirements: [{
              requirement: "^3.2.2",
              file: "package.json",
              groups: ["dependencies"],
              source: { type: "registry", url: "https://registry.npmjs.org" }
            }],
            package_manager: "npm_and_yarn"
          ),
          Dependabot::Dependency.new(
            name: name,
            version: "6.0.2",
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        ])
      end
    end
  end

  describe "missing package.json manifest file" do
    let(:child_class) do
      Class.new(described_class) do
        def check_required_files
          %w(manifest).each do |filename|
            unless get_original_file(filename)
              raise Dependabot::DependencyFileNotFound.new(nil,
                                                           "package.json not found.")
            end
          end
        end
      end
    end
    let(:parser_instance) do
      child_class.new(dependency_files: files, source: source)
    end
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "gocardless/bump",
        directory: "/"
      )
    end

    let(:gemfile) do
      Dependabot::DependencyFile.new(
        content: "a",
        name: "manifest",
        directory: "/path/to"
      )
    end
    let(:files) { [gemfile] }

    describe ".new" do
      context "when the required file is present" do
        let(:files) { [gemfile] }

        it "doesn't raise" do
          expect { parser_instance }.not_to raise_error
        end
      end

      context "when the required file is missing" do
        let(:files) { [] }

        it "raises" do
          expect { parser_instance }.to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    describe "#get_original_file" do
      subject { parser_instance.send(:get_original_file, filename) }

      context "when the requested file is present" do
        let(:filename) { "manifest" }

        it { is_expected.to eq(gemfile) }
      end

      context "when the requested file is not present" do
        let(:filename) { "package.json" }

        it { is_expected.to be_nil }
      end
    end
  end
end
