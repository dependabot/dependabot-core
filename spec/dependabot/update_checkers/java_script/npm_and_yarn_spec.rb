# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::JavaScript::NpmAndYarn do
  it_behaves_like "an update checker"

  let(:registry_listing_url) { "https://registry.npmjs.org/etag" }
  let(:registry_response) do
    fixture("javascript", "npm_responses", "etag.json")
  end
  before do
    stub_request(:get, registry_listing_url).
      to_return(status: 200, body: registry_response)
    stub_request(:get, registry_listing_url + "/latest").
      to_return(status: 200, body: "{}")
    stub_request(:get, registry_listing_url + "/1.7.0").
      to_return(status: 200)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end
  let(:ignored_versions) { [] }
  let(:dependency_files) { [package_json] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "etag",
      version: "1.0.0",
      requirements: [
        { file: "package.json", requirement: "^1.0.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }

      context "with no version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: "^0.9.0",
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to be_truthy }
      end
    end

    context "given an up-to-date dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.7.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to be_falsey }

      context "with no version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [{
              file: "package.json",
              requirement: requirement,
              groups: [],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        context "and a requirement that exactly matches" do
          let(:requirement) { "^1.7.0" }
          it { is_expected.to be_falsey }
        end

        context "and a requirement that covers but doesn't exactly match" do
          let(:requirement) { "^1.6.0" }
          it { is_expected.to be_falsey }
        end
      end
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(
            status: 200,
            body: fixture("javascript", "npm_responses", "etag.json")
          )
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep/1.7.0").
          to_return(status: 200)
        allow_any_instance_of(described_class::VersionResolver).
          to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("1.7.0"))
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it "delegates to LatestVersionFinder" do
      expect(described_class::LatestVersionFinder).to receive(:new).with(
        dependency: dependency,
        credentials: credentials,
        dependency_files: dependency_files,
        ignored_versions: ignored_versions
      ).and_call_original

      expect(checker.latest_version).to eq(Gem::Version.new("1.7.0"))
    end

    it "only hits the registry once" do
      checker.latest_version
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: current_version,
          requirements: [{
            requirement: req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: ref
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/is-number" }
      let(:registry_response) do
        fixture("javascript", "npm_responses", "is_number.json")
      end
      let(:current_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", upload_pack_fixture),
            headers: git_header
          )
        stub_request(:get, registry_listing_url + "/4.0.0").
          to_return(status: 200)

        repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
        stub_request(:get, repo_url + "/compare/4.0.0...#{ref}").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
      end
      let(:upload_pack_fixture) { "is-number" }
      let(:commit_compare_response) do
        fixture("github", "commit_compare_diverged.json")
      end

      context "with a branch" do
        let(:ref) { "master" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the head of the branch" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "that doesn't exist" do
          let(:ref) { "non-existant" }
          let(:req) { nil }

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).to eq(current_version)
          end
        end

        context "that is behind the latest release" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_behind.json")
          end

          it "updates to the latest release" do
            expect(checker.latest_version).to eq(Gem::Version.new("4.0.0"))
          end

          context "when the registry doesn't return a latest release" do
            let(:registry_response) do
              fixture("javascript", "npm_responses", "no_latest.json")
            end

            it "updates to the latest release" do
              expect(checker.latest_version).to eq(Gem::Version.new("4.0.0"))
            end
          end
        end

        context "for a dependency that doesn't have a release" do
          before do
            stub_request(:get, registry_listing_url).
              to_return(status: 404, body: "{}")
          end

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).
              to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end

        context "for a dependency that 405s" do
          before do
            stub_request(:get, registry_listing_url).
              to_return(status: 405, body: "{}")
          end

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).
              to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
          end
        end
      end

      context "with a commit ref" do
        let(:ref) { "d5ac058" }
        let(:req) { nil }

        it "returns the current version" do
          expect(checker.latest_version).to eq(current_version)
        end

        context "that is behind the latest release" do
          let(:commit_compare_response) do
            fixture("github", "commit_compare_behind.json")
          end

          it "updates to the latest release" do
            expect(checker.latest_version).to eq(Gem::Version.new("4.0.0"))
          end
        end
      end

      context "with a ref that looks like a version" do
        let(:ref) { "2.0.0" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "but there are no tags" do
          let(:upload_pack_fixture) { "no_tags" }
          it { is_expected.to be_nil }
        end
      end

      context "with a requirement" do
        let(:ref) { "master" }
        let(:req) { "^2.0.0" }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "but there are no tags" do
          let(:upload_pack_fixture) { "no_tags" }
          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    context "for a sub-dependency" do
      context "using yarn" do
        let(:dependency_files) { [package_json, yarn_lock] }
        let(:manifest_fixture_name) { "no_lockfile_change.json" }
        let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

        let(:registry_listing_url) { "https://registry.npmjs.org/acorn" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "acorn",
            version: "5.1.1",
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        let(:yarn_lock) do
          Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content:
              fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
          )
        end

        # Note: The latest vision is 6.0.2, but we can't reach it as other
        # dependencies constrain us
        it { is_expected.to eq(Gem::Version.new("5.7.3")) }
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }

    context "with a non-git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: requirements,
          package_manager: "npm_and_yarn"
        )
      end
      let(:requirements) do
        [{
          file: "package.json",
          requirement: req_string,
          groups: [],
          source: nil
        }]
      end
      let(:req_string) { "^1.0.0" }

      it "delegates to LatestVersionFinder" do
        expect(described_class::LatestVersionFinder).to receive(:new).with(
          dependency: dependency,
          credentials: credentials,
          dependency_files: dependency_files,
          ignored_versions: ignored_versions
        ).and_call_original

        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("1.7.0"))
      end
    end

    context "for a sub-dependency" do
      context "using yarn" do
        let(:dependency_files) { [package_json, yarn_lock] }
        let(:manifest_fixture_name) { "no_lockfile_change.json" }
        let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

        let(:registry_listing_url) { "https://registry.npmjs.org/acorn" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "acorn",
            version: "5.1.1",
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        let(:yarn_lock) do
          Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content:
              fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
          )
        end

        # Note: The latest vision is 6.0.2, but we can't reach it as other
        # dependencies constrain us
        it { is_expected.to eq(Gem::Version.new("5.7.3")) }
      end
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: current_version,
          requirements: [{
            requirement: req,
            file: "package.json",
            groups: ["devDependencies"],
            source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: ref
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end
      let(:current_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "is-number"),
            headers: git_header
          )
      end

      context "with a branch" do
        let(:ref) { "master" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the head of the branch" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end
      end

      context "with a ref that looks like a version" do
        let(:ref) { "2.0.0" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq(current_version)
        end
      end

      context "with a requirement" do
        let(:ref) { "master" }
        let(:req) { "^2.0.0" }

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq(current_version)
        end
      end
    end
  end

  describe "#updated_requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.0",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: nil
      }]
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          updated_source: nil,
          latest_version: "1.7.0",
          latest_resolvable_version: "1.7.0",
          update_strategy: :bump_versions
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "package.json",
            requirement: "^1.7.0",
            groups: [],
            source: nil
          }]
        )
    end

    context "when a requirements_update_strategy has been specified" do
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          requirements_update_strategy: :bump_versions_if_necessary
        )
      end

      it "uses the specified requirements_update_strategy" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_version: "1.7.0",
            latest_resolvable_version: "1.7.0",
            update_strategy: :bump_versions_if_necessary
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }]
          )
      end
    end

    context "with a library (that has a lockfile)" do
      # We've already stubbed hitting the registry for etag (since it's also
      # the dependency we're checking in this spec)
      let(:manifest_fixture_name) { "etag.json" }

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: nil,
            latest_version: "1.7.0",
            latest_resolvable_version: "1.7.0",
            update_strategy: :widen_ranges
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }]
          )
      end
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
          requirements: dependency_requirements,
          package_manager: "npm_and_yarn"
        )
      end
      let(:dependency_requirements) do
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
      end
      let(:registry_listing_url) { "https://registry.npmjs.org/is-number" }
      let(:registry_response) do
        fixture("javascript", "npm_responses", "is_number.json")
      end
      let(:commit_compare_response) do
        fixture("github", "commit_compare_diverged.json")
      end

      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "is-number"),
            headers: git_header
          )
        repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
        stub_request(:get, repo_url + "/compare/4.0.0...master").
          to_return(
            status: 200,
            body: commit_compare_response,
            headers: { "Content-Type" => "application/json" }
          )
        stub_request(:get, registry_listing_url + "/4.0.0").
          to_return(status: 200)
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: {
              type: "git",
              url: "https://github.com/jonschlinkert/is-number",
              branch: nil,
              ref: "master"
            },
            latest_version: "4.0.0",
            latest_resolvable_version: "4.0.0",
            update_strategy: :bump_versions
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              file: "package.json",
              requirement: "^4.0.0",
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

      context "that should switch to a registry source" do
        let(:commit_compare_response) do
          fixture("github", "commit_compare_behind.json")
        end

        let(:dependency_requirements) do
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
        end

        it "delegates to the RequirementsUpdater" do
          expect(described_class::RequirementsUpdater).
            to receive(:new).
            with(
              requirements: dependency_requirements,
              updated_source: nil,
              latest_version: "4.0.0",
              latest_resolvable_version: "4.0.0",
              update_strategy: :bump_versions
            ).
            and_call_original
          expect(checker.updated_requirements).
            to eq(
              [{
                file: "package.json",
                requirement: "^4.0.0",
                groups: ["devDependencies"],
                source: nil
              }]
            )
        end
      end
    end
  end
end
