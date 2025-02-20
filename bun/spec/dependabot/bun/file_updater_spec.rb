# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::FileUpdater do
  let(:repo_contents_path) { nil }
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:source) { nil }
  let(:previous_requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.1",
      groups: ["dependencies"],
      source: source
    }]
  end
  let(:requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.2",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_version) { "0.0.1" }
  let(:version) { "0.0.2" }
  let(:dependency_name) { "fetch-factory" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "bun"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com"
    })]
  end
  let(:dependencies) { [dependency] }
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  # Variable to control the npm fallback version feature flag
  let(:npm_fallback_version_above_v6_enabled) { true }
  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    FileUtils.mkdir_p(tmp_path)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_fallback_version_above_v6).and_return(npm_fallback_version_above_v6_enabled)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_v6_deprecation_warning).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:avoid_duplicate_updates_package_json).and_return(false)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "package.json",
          "subdirectory/package.json",
          "apps/dependabot_business/package.json",
          "packages/package1/package.json",
          "bun.lock",
          "subdirectory/bun.lock"
        ]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "Gemfile",
          "Gemfile.lock",
          "package-lock.json",
          "npm-shrinkwrap.json",
          "yarn.lock",
          "pnpm-lock.yaml",
          "pnpm-workspace.yaml",
          "subdirectory/package-lock.json",
          "subdirectory/npm-shrinkwrap.json",
          "subdirectory/yarn.lock",
          "subdirectory/pnpm-lock.yaml",
          "packages/package2/yarn.lock",
          ".yarn/install-state.gz",
          ".yarn/cache/@es-test-npm-0.46.0-d544b36047-96010ece49.zip",
          ".pnp.js",
          ".pnp.cjs"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:updated_package_json) { updated_files.find { |f| f.name == "package.json" } }
    let(:updated_bun_lock) { updated_files.find { |f| f.name == "bun.lock" } }

    context "without a lockfile" do
      let(:files) { project_dependency_files("javascript/simple_manifest") }

      its(:length) { is_expected.to eq(1) }

      context "when nothing has changed" do
        let(:requirements) { previous_requirements }

        specify { expect { updated_files }.to raise_error(/No files/) }
      end
    end

    context "with multiple dependencies" do
      let(:npm_fallback_version_above_v6_enabled) { false }

      let(:files) { project_dependency_files("javascript/multiple_updates") }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.8.1",
            previous_version: "1.0.1",
            requirements: [{
              file: "package.json",
              requirement: "^1.8.1",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^1.0.1",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "bun"
          ),
          Dependabot::Dependency.new(
            name: "is-number",
            version: "4.0.0",
            previous_version: "2.0.0",
            requirements: [{
              file: "package.json",
              requirement: "^4.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^2.0.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "bun"
          )
        ]
      end

      it "updates both dependencies" do
        parsed_package = JSON.parse(updated_package_json.content)
        expect(parsed_package["dependencies"]["is-number"])
          .to eq("^4.0.0")
        expect(parsed_package["dependencies"]["etag"])
          .to eq("^1.8.1")
      end

      context "when dealing with lockfile only update" do
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "etag",
              version: "1.2.0",
              previous_version: "1.0.1",
              requirements: [{
                file: "package.json",
                requirement: "^1.0.1",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^1.0.1",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "bun"
            ),
            Dependabot::Dependency.new(
              name: "is-number",
              version: "2.1.0",
              previous_version: "2.0.0",
              requirements: [{
                file: "package.json",
                requirement: "^2.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "^2.0.0",
                groups: ["dependencies"],
                source: nil
              }],
              package_manager: "bun"
            )
          ]
        end

        it "updates both dependencies" do
          expect(updated_files.map(&:name))
            .to match_array(%w(bun.lock))

          expect(updated_bun_lock.content)
            .to include("is-number@2.1.0")
          expect(updated_bun_lock.content)
            .to include("etag@1.2.0")
        end
      end
    end

    context "with a git dependency" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:dependency_name) { "is-number" }
      let(:requirements) do
        [{
          requirement: req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: old_req,
          file: "package.json",
          groups: ["devDependencies"],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      let(:version) { "0c6b15a88bc10cd47f67a09506399dfc9ddc075d" }

      context "without a requirement or reference" do
        let(:req) { nil }
        let(:ref) { "master" }
        let(:old_req) { nil }
        let(:old_ref) { "master" }

        let(:files) { project_dependency_files("bun/github_dependency_no_ref") }

        it "only updates the lockfile" do
          expect(updated_files.map(&:name))
            .to match_array(%w(bun.lock))
        end

        it "correctly update the lockfiles" do
          expect(updated_bun_lock.content)
            .to include("is-number@github:jonschlinkert/is-number#98e8ff1")
        end
      end
    end

    context "when a wildcard is specified" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("bun/wildcard") }

      let(:version) { "0.2.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "*",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) { requirements }

      it "only updates the lockfiles" do
        expect(updated_files.map(&:name))
          .to match_array(%w(bun.lock))

        expect(updated_bun_lock.content)
          .to include("fetch-factory@0.2.0")
      end
    end
  end

  describe "without a package.json file" do
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
    let(:updater_instance) do
      child_class.new(
        dependency_files: files,
        dependencies: [dependency],
        credentials: [{
          "type" => "git_source",
          "host" => "github.com"
        }]
      )
    end

    let(:manifest) do
      Dependabot::DependencyFile.new(
        content: "a",
        name: "manifest",
        directory: "/path/to"
      )
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        version: "1.5.0",
        package_manager: "bundler",
        requirements:
          [{ file: "manifest", requirement: "~> 1.4.0", groups: [], source: nil }]
      )
    end
    let(:files) { [manifest] }

    describe "new file updater" do
      subject { -> { updater_instance } }

      context "when the required file is present" do
        let(:files) { [manifest] }

        it "doesn't raise" do
          expect { updater_instance }.not_to raise_error
        end
      end

      context "when the required file is missing" do
        let(:files) { [] }

        it "raises" do
          expect { updater_instance }.to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    describe "#get_original_file" do
      subject { updater_instance.send(:get_original_file, filename) }

      context "when the requested file is present" do
        let(:filename) { "manifest" }

        it { is_expected.to eq(manifest) }
      end

      context "when the requested file is not present" do
        let(:filename) { "package.json" }

        it { is_expected.to be_nil }
      end
    end
  end
end
