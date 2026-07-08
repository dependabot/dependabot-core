# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub"

RSpec.describe Dependabot::Nub::FileUpdater do
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
      package_manager: "nub"
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com"
      }
    )]
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

  before do
    FileUtils.mkdir_p(tmp_path)
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:updated_package_json) { updated_files.find { |f| f.name == "package.json" } }
    let(:updated_nub_lock) { updated_files.find { |f| f.name == "nub.lock" } }

    context "without a lockfile" do
      let(:files) { project_dependency_files("javascript/simple_manifest") }

      its(:length) { is_expected.to eq(1) }

      context "when nothing has changed" do
        let(:requirements) { previous_requirements }

        specify { expect { updated_files }.to raise_error(/No files/) }
      end
    end

    context "with multiple dependencies" do
      let(:files) { project_dependency_files("javascript/multiple_updates") }
      let(:repo_contents_path) { build_tmp_repo("javascript/multiple_updates", path: "projects") }

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
            package_manager: "nub"
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
            package_manager: "nub"
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
              package_manager: "nub"
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
              package_manager: "nub"
            )
          ]
        end

        it "updates both dependencies" do
          expect(updated_files.map(&:name))
            .to match_array(%w(nub.lock))

          expect(updated_nub_lock.content)
            .to include("is-number@2.1.0")
          expect(updated_nub_lock.content)
            .to include("etag@1.2.0")
        end

        it "updates the lockfile via a single `nub update <pkg>@<ver>` then settles" do
          allow(Dependabot::Nub::Helpers).to receive(:run_nub_command).and_call_original

          updated_files

          # One `nub update <pkg>@<ver> --no-save` pins the chosen versions in the lockfile (nub >= 0.4.1,
          # works for transitive deps too); a plain lockfile-only install settles the rest.
          expect(Dependabot::Nub::Helpers).to have_received(:run_nub_command).with(
            a_string_matching(/^update .+ --lockfile-only --no-save --ignore-scripts$/),
            fingerprint: "update <dependency_updates> --lockfile-only --no-save --ignore-scripts"
          )
          expect(Dependabot::Nub::Helpers).to have_received(:run_nub_command).with(
            "install --lockfile-only --ignore-scripts",
            fingerprint: "install --lockfile-only --ignore-scripts"
          )
        end
      end
    end

    context "with a git dependency" do
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

      context "when the git ref changes (e.g. a version-tag bump)" do
        # The Dependabot-chosen update moves the manifest ref, so PackageJsonUpdater rewrites
        # `#2.0.0` -> `#2.1.0` in package.json and nub's lockfile-only install re-resolves the
        # git dep to the new tag's commit. This is the supported git-dependency update path.
        let(:req) { nil }
        let(:ref) { "2.1.0" }
        let(:old_req) { nil }
        let(:old_ref) { "2.0.0" }
        let(:previous_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
        let(:version) { "0024f0f6552b6375712d93a7eadaa48810588736" }

        let(:files) { project_dependency_files("nub/github_dependency_versioned") }
        let(:repo_contents_path) { build_tmp_repo("nub/github_dependency_versioned", path: "projects") }

        it "re-resolves the git dependency to the new ref's commit in the lockfile" do
          expect(updated_files.map(&:name)).to include("nub.lock")
          expect(updated_nub_lock.content)
            .to include("codeload.github.com/jonschlinkert/is-number/tar.gz/0024f0f6")
          expect(updated_nub_lock.content)
            .not_to include("tar.gz/d5ac0584")
        end
      end

      context "without a requirement or reference (same-branch SHA advance)" do
        let(:req) { nil }
        let(:ref) { "master" }
        let(:old_req) { nil }
        let(:old_ref) { "master" }

        let(:files) { project_dependency_files("nub/github_dependency_no_ref") }
        let(:repo_contents_path) { build_tmp_repo("nub/github_dependency_no_ref", path: "projects") }

        it "only updates the lockfile" do
          skip("Unsupported by nub's CLI: the manifest ref is unchanged (master -> master), so " \
               "PackageJsonUpdater produces no manifest edit and nub's conservative lockfile-only " \
               "install keeps the already-locked SHA. Advancing a git dep on the same branch needs " \
               "a nub-side force-re-resolution capability (`update <pkg>@<sha>` / a targeted refresh) " \
               "that nub does not yet expose. Ref-CHANGE git updates DO work (see the context above).")
          expect(updated_files.map(&:name))
            .to match_array(%w(nub.lock))
        end

        it "correctly update the lockfiles" do
          skip("Unsupported by nub's CLI: same-branch SHA advance, see the sibling example above.")
          # nub records a github dependency by its resolved codeload tarball URL (pnpm-v9 form).
          expect(updated_nub_lock.content)
            .to include("codeload.github.com/jonschlinkert/is-number/tar.gz/98e8ff1")
        end
      end
    end

    context "when a wildcard is specified" do
      let(:files) { project_dependency_files("nub/wildcard") }
      let(:repo_contents_path) { build_tmp_repo("nub/wildcard", path: "projects") }

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
          .to match_array(%w(nub.lock))

        expect(updated_nub_lock.content)
          .to include("fetch-factory@0.2.0")
      end
    end

    context "with a transitive (sub-)dependency security update" do
      # lodash is a transitive dep of fetch-factory, not present in package.json. Dependabot drives
      # these for security advisories; `nub update lodash@<ver>` bumps it in the lockfile only.
      let(:files) { project_dependency_files("nub/transitive_update") }
      let(:repo_contents_path) { build_tmp_repo("nub/transitive_update", path: "projects") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "lodash",
          version: "4.17.21",
          previous_version: "3.10.1",
          requirements: [],
          previous_requirements: [],
          package_manager: "nub"
        )]
      end

      it "bumps the transitive dependency in the lockfile" do
        expect(updated_files.map(&:name)).to match_array(%w(nub.lock))
        expect(updated_nub_lock.content).to include("lodash@4.17.21")
        expect(updated_nub_lock.content).not_to include("lodash@3.10.1")
      end
    end
  end

  describe "without a package.json file" do
    let(:child_class) do
      Class.new(described_class) do
        def check_required_files
          %w(manifest).each do |filename|
            next if get_original_file(filename)

            raise Dependabot::DependencyFileNotFound.new(
              nil,
              "package.json not found."
            )
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
