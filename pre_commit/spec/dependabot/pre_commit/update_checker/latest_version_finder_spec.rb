# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit/update_checker/latest_version_finder"
require "dependabot/pre_commit/helpers"

RSpec.describe Dependabot::PreCommit::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: update_cooldown
    )
  end

  let(:dependency_name) { "pre-commit/pre-commit-hooks" }
  let(:reference) { "v4.4.0" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:source_details) { Dependabot::GitCommitChecker::SourceDetails.from_hash(dependency_source) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/#{dependency_name}",
      version: "4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: dependency_source
      }],
      package_manager: "pre_commit"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:update_cooldown) { nil }
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs?service=git-upload-pack"
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", "pre-commit-hooks"),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  describe "#latest_release_version" do
    subject(:latest_release_version) { finder.latest_release_version }

    context "when pinned to a version tag" do
      let(:reference) { "v4.4.0" }

      it "returns the latest version" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release_version.to_s).to eq("6.0.0")
      end
    end

    context "when pinned to a commit SHA with a known tag" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return("v4.4.0")
      end

      it "returns the latest tagged version" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when pinned to a commit SHA without a known tag" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:head_commit_for_pinned_ref).and_return("abc123def456")
      end

      it "falls back to latest commit SHA" do
        expect(latest_release_version).to be_a(String)
      end
    end

    context "when pinned to a commit SHA with a frozen version comment" do
      let(:reference) { "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: nil,
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source,
            metadata: { comment: "# frozen: v4.4.0" }
          }],
          package_manager: "pre_commit"
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
      end

      it "returns the latest tagged version using comment metadata" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { [">= 6.0.0"] }

      it "filters out ignored versions" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release_version.to_s.split(".").first.to_i).to be < 6
      end
    end

    context "with a prerelease tag newer than the latest stable" do
      before do
        stub_request(:get, service_pack_url)
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "pre-commit-hooks-with-prerelease.txt"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      it "excludes the prerelease and returns the latest stable version" do
        expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(latest_release_version.to_s).to eq("6.0.0")
      end

      context "when the current version is itself a prerelease" do
        let(:reference) { "v7.0.0-rc1" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/#{dependency_name}",
            version: "7.0.0-rc1",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: dependency_source
            }],
            package_manager: "pre_commit"
          )
        end

        it "allows a newer prerelease as an update" do
          expect(latest_release_version).to be_a(Dependabot::PreCommit::Version)
          expect(latest_release_version.to_s).to eq("7.0.0.pre.rc2")
        end
      end
    end
  end

  describe "cooldown filtering" do
    let(:reference) { "v4.4.0" }

    context "with cooldown configured" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      it "accepts cooldown configuration without error" do
        expect { finder.latest_release_version }.not_to raise_error
        expect(finder.latest_release_version).to be_a(Dependabot::PreCommit::Version)
      end

      it "returns a version when cooldown is applied" do
        result = finder.latest_release_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "when latest version is in cooldown" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      it "falls back to a previous version not in cooldown" do
        recent_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")
        old_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Gem::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }
        older_tag = {
          tag: "v5.0.0",
          version: "5.0.0",
          commit_sha: "older_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag, older_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(recent_date, old_date)

        result = finder.latest_release_version
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("5.0.0")
      end

      it "returns current version when no fallback candidates exist" do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([])

        result = finder.latest_release_version
        expect(result.to_s).to eq("4.4.0")
      end

      it "returns nil from latest_version_tag when all versions are in cooldown" do
        recent_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(recent_date)

        # Trigger cooldown evaluation
        finder.latest_release_version

        # latest_version_tag must be nil so that sha1_version_up_to_date?
        # does not resolve a commit SHA for the cooldown-blocked version
        expect(finder.latest_version_tag).to be_nil
      end

      it "returns the cooldown-selected tag from latest_version_tag" do
        recent_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")
        old_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }
        older_tag = {
          tag: "v5.0.0",
          version: Dependabot::PreCommit::Version.new("5.0.0"),
          commit_sha: "older_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag, older_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(recent_date, old_date)

        # Trigger cooldown evaluation
        finder.latest_release_version

        # latest_version_tag should return the cooldown-selected tag (v5.0.0)
        expect(finder.latest_version_tag).to eq(older_tag)
      end

      context "with v-prefixed version in dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/#{dependency_name}",
            version: "v4.4.0",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: dependency_source
            }],
            package_manager: "pre_commit"
          )
        end

        it "does not select versions older than the current pinned ref" do
          # v3.0.0 is older than v4.4.0 — must not be selected even if not in cooldown
          old_tag = {
            tag: "v3.0.0",
            version: Dependabot::PreCommit::Version.new("3.0.0"),
            commit_sha: "old_sha"
          }
          latest_tag = {
            tag: "v6.0.0",
            version: Dependabot::PreCommit::Version.new("6.0.0"),
            commit_sha: "latest_sha"
          }

          recent_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")

          allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
            .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
            .and_return([latest_tag, old_tag])
          allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
            .to receive(:dependency_source_details)
            .and_return(source_details)
          allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
          allow(Dir).to receive(:chdir).and_yield
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(/git clone --bare/, any_args).and_return("")
          # All remaining candidates (v6.0.0) are in cooldown
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(/git for-each-ref/, hash_including(fingerprint: anything))
            .and_return(recent_date)

          result = finder.latest_release_version
          expect(result.to_s).to eq("4.4.0")
        end
      end
    end

    context "with nil cooldown" do
      let(:update_cooldown) { nil }

      it "returns latest version without filtering" do
        expect(finder.latest_release_version).to be_a(Dependabot::PreCommit::Version)
        expect(finder.latest_release_version.to_s).to eq("6.0.0")
      end
    end

    context "when pinned to a SHA with frozen comment and cooldown enabled" do
      let(:reference) { "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/#{dependency_name}",
          version: "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".pre-commit-config.yaml",
            source: dependency_source,
            metadata: { comment: "# frozen: v5.0.0" }
          }],
          package_manager: "pre_commit"
        )
      end
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      before do
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_pinned_sha).and_return(nil)
      end

      it "uses the frozen comment version for cooldown comparison" do
        old_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        v6_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "3e8a8703264a2f4a69428a0aa4dcb512790b2c8c"
        }
        v5_tag = {
          tag: "v5.0.0",
          version: Dependabot::PreCommit::Version.new("5.0.0"),
          commit_sha: "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b"
        }
        v4_tag = {
          tag: "v4.4.0",
          version: Dependabot::PreCommit::Version.new("4.4.0"),
          commit_sha: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions)
          .and_return([v6_tag, v5_tag, v4_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_raise("unexpected precision filtering")
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(old_date)

        result = finder.latest_release_version
        # Should return v6.0.0 (not nil) because the frozen comment tells us
        # current version is v5.0.0, so only v6.0.0 is a candidate,
        # and it's outside the cooldown window
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("6.0.0")
      end

      it "does not falsely flag all versions as in cooldown" do
        recent_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")
        old_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        v6_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "3e8a8703264a2f4a69428a0aa4dcb512790b2c8c"
        }
        v5_1_tag = {
          tag: "v5.1.0",
          version: Dependabot::PreCommit::Version.new("5.1.0"),
          commit_sha: "abc123"
        }
        v5_tag = {
          tag: "v5.0.0",
          version: Dependabot::PreCommit::Version.new("5.0.0"),
          commit_sha: "cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions)
          .and_return([v6_tag, v5_1_tag, v5_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_raise("unexpected precision filtering")
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # v6.0.0 is in cooldown, but v5.1.0 is not
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(recent_date, old_date)

        result = finder.latest_release_version
        # Should fall back to v5.1.0 (> v5.0.0 and outside cooldown)
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("5.1.0")
      end
    end

    context "when tag creation date differs from commit date" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      it "uses tag creation date (not commit date) for cooldown evaluation" do
        # Tag was created today but points to a commit from 30 days ago.
        # The tag creation date (today) should be used for cooldown, meaning
        # the version IS in cooldown. If the commit date were used instead,
        # the version would incorrectly bypass cooldown.
        tag_creation_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # for-each-ref returns the tag creation date (today) — in cooldown
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(tag_creation_date)

        result = finder.latest_release_version
        # Should stay on current version because tag was just created (in cooldown)
        expect(result.to_s).to eq("4.4.0")
      end

      it "falls back to commit date when for-each-ref returns empty" do
        # Simulates a lightweight tag that for-each-ref can't find (empty result)
        # Should fall back to git show %cd
        old_commit_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # for-each-ref returns empty (tag not found)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return("")
        # Fallback to git show returns old commit date (outside cooldown)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git show --no-patch/, hash_including(fingerprint: anything))
          .and_return(old_commit_date)

        result = finder.latest_release_version
        # Should accept version because fallback commit date is old (outside cooldown)
        expect(result.to_s).to eq("6.0.0")
      end

      it "correctly applies cooldown with annotated tag that points to old commit" do
        # Annotated tag created 2 days ago pointing to a commit from 30 days ago
        # Cooldown is 7 days — tag creation date (2 days) is within cooldown
        tag_creation_date = (Time.now - (2 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")
        old_tag_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }
        older_tag = {
          tag: "v5.0.0",
          version: Dependabot::PreCommit::Version.new("5.0.0"),
          commit_sha: "older_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag, older_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # v6.0.0 tag was created 2 days ago (in cooldown), v5.0.0 tag 30 days ago (outside)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(tag_creation_date, old_tag_date)

        result = finder.latest_release_version
        # Should skip v6.0.0 (in cooldown) and select v5.0.0 (outside cooldown)
        expect(result.to_s).to eq("5.0.0")
      end
    end

    context "when GitHub Release published_at is available" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7
        )
      end

      it "uses GitHub Release published_at for cooldown (bypasses git clone)" do
        recent_published_at = Time.now - (2 * 24 * 60 * 60) # 2 days ago

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)

        # Mock GitHub Release with recent published_at (in cooldown)
        mock_release = Struct.new(:tag_name, :published_at, :prerelease)
                             .new("v6.0.0", recent_published_at, false)
        mock_client = instance_double(Octokit::Client, releases: [mock_release])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        # Should NOT clone the repo since we got the date from Octokit
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command).with(/git clone/)

        result = finder.latest_release_version
        # v6.0.0 is in cooldown (published 2 days ago, cooldown is 7 days)
        expect(result.to_s).to eq("4.4.0")
      end

      it "falls back to git when no GitHub Release exists for the tag" do
        old_date = (Time.now - (30 * 24 * 60 * 60)).utc.strftime("%Y-%m-%d %H:%M:%S %z")

        latest_tag = {
          tag: "v6.0.0",
          version: Dependabot::PreCommit::Version.new("6.0.0"),
          commit_sha: "latest_sha"
        }

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tags_for_allowed_versions_matching_existing_precision)
          .and_return([latest_tag])
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)

        # No release for this tag
        mock_client = instance_double(Octokit::Client, releases: [])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        # Falls back to git clone
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(old_date)

        result = finder.latest_release_version
        # Falls back to for-each-ref, date is old (outside cooldown)
        expect(result.to_s).to eq("6.0.0")
      end
    end
  end

  describe "version precision" do
    context "with shortened version ref" do
      let(:reference) { "v4.4" }

      it "handles shortened version refs" do
        result = finder.latest_release_version
        expect(result).to be_a(Dependabot::PreCommit::Version)
      end
    end

    context "with full version ref" do
      let(:reference) { "v4.4.0" }

      it "handles full version refs" do
        result = finder.latest_release_version
        expect(result).to be_a(Dependabot::PreCommit::Version)
        expect(result.to_s).to eq("6.0.0")
      end
    end
  end
end
