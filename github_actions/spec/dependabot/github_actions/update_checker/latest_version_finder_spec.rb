# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/github_actions/update_checker/latest_version_finder"

namespace = Dependabot::GithubActions::UpdateChecker
RSpec.describe namespace::LatestVersionFinder do
  let(:upload_pack_fixture) { "setup-node" }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:service_pack_url) do
    "https://github.com/#{dependency_name}.git/info/refs" \
      "?service=git-upload-pack"
  end
  let(:reference) { "master" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/#{dependency_name}",
      ref: reference,
      branch: nil
    }
  end
  let(:source_details) { Dependabot::GitCommitChecker::SourceDetails.from_hash(dependency_source) }
  let(:dependency_version) do
    return unless Dependabot::GithubActions::Version.correct?(reference)

    Dependabot::GithubActions::Version.new(reference).to_s
  end
  let(:dependency_name) { "actions/setup-node" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source,
        metadata: { declaration_string: "#{dependency_name}@master" }
      }],
      package_manager: "github_actions"
    )
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
    )
  end

  before do
    stub_request(:get, service_pack_url)
      .to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end

  shared_context "with multiple git sources" do
    let(:upload_pack_fixture) { "checkout" }
    let(:dependency_name) { "actions/checkout" }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "actions/checkout",
        version: nil,
        package_manager: "github_actions",
        requirements: [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          }
        }]
      )
    end
  end

  describe "#latest_release_version" do
    subject(:latest_release_version) { finder.latest_release_version }

    let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }

    context "when given a dependency has a branch reference" do
      let(:reference) { "master" }

      it { is_expected.to eq(tip_of_master) }
    end

    context "when a dependency has a tag reference and a branch similar to the tag" do
      let(:upload_pack_fixture) { "download-artifact" }
      let(:reference) { "v2" }

      it { is_expected.to eq(Dependabot::GithubActions::Version.new("3")) }
    end

    context "when a git commit SHA pointing to the tip of a branch not named like a version" do
      let(:upload_pack_fixture) { "setup-node" }
      let(:tip_of_master) { "d963e800e3592dd31d6c76252092562d0bc7a3ba" }
      let(:reference) { tip_of_master }

      it "considers the commit itself as the latest version" do
        expect(latest_release_version).to eq(tip_of_master)
      end
    end

    context "when a git commit SHA pointing to the tip of a branch named like a version" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "when a branch named like a higher version" do
        let(:tip_of_v6) { "205a4bde2b6ddf941a102fb50320ea1aa9338233" }

        let(:reference) { tip_of_v6 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end

      context "when no branch named like a higher version" do
        let(:tip_of_v10) { "34684effe7451ea95f60397e56ba34c06daced68" }

        let(:reference) { tip_of_v10 }

        it { is_expected.to eq(Gem::Version.new("10.5")) }
      end
    end

    context "when using a dependency with multiple git refs" do
      include_context "with multiple git sources"

      it "returns the expected value" do
        expect(latest_release_version).to eq(Gem::Version.new("3.5.2"))
      end
    end
  end

  describe "#lowest_security_fix_release" do
    subject(:lowest_security_fix_release) { finder.lowest_security_fix_release }

    let(:upload_pack_fixture) { "ghas-to-csv" }
    let(:dependency_version) { "0.4.0" }
    let(:dependency_name) { "some-natalie/ghas-to-csv" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "github_actions",
          vulnerable_versions: ["< 1.0"]
        )
      ]
    end

    context "when a supported newer version is available" do
      it "updates to the least new supported version" do
        expect(lowest_security_fix_release).to eq(
          (
                    { tag: "v1",
                      version: Dependabot::GithubActions::Version.new("1.0.0"),
                      commit_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a",
                      tag_sha: "d0b521928fa734513b5cd9c7d9d8e09db50e884a" }
                  )
        )
      end
    end

    context "with ignored versions" do
      let(:ignored_versions) { ["= 1.0.0"] }

      it "doesn't return ignored versions" do
        expect(lowest_security_fix_release).to eq(
          { commit_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08", tag: "v2",
            tag_sha: "bb178d2de54771e6f9332a2b1d55546cf2bc3e08",
            version: Dependabot::GithubActions::Version.new("2.0.0") }
        )
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { finder.lowest_security_fix_release }

    before do
      allow(finder)
        .to receive(:lowest_security_fix_release)
        .and_return(Dependabot::GithubActions::Version.new("2.0.0"))
    end

    it { is_expected.to eq(Dependabot::GithubActions::Version.new("2.0.0")) }
  end

  describe "#latest_version_tag_respecting_cooldown" do
    subject(:latest_version_tag_respecting_cooldown) { finder.latest_version_tag_respecting_cooldown }

    context "when cooldown filters out the latest major tag" do
      let(:dependency_name) { "actions/checkout" }
      let(:upload_pack_fixture) { "checkout" }
      let(:reference) { "v2" }
      let(:dependency_version) { "2" }
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "v2",
          branch: nil
        }
      end
      let(:finder) do
        described_class.new(
          dependency: dependency,
          dependency_files: [],
          credentials: github_credentials,
          security_advisories: security_advisories,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
        )
      end

      before do
        # The shared GitCommitChecker cooldown returns the newest tag outside
        # its window; here the latest v3.x is cooling down so it falls back to
        # v2.7.0. Date resolution itself is covered by git_commit_checker_spec.
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_latest_version)
          .and_return(
            tag: "v2.7.0",
            version: Dependabot::GithubActions::Version.new("2.7.0"),
            commit_sha: "ee0669bd1cc54295c223e0bb666b733df41de1c5"
          )
      end

      it "returns the tag hash for the selected cooled-down release" do
        expect(latest_version_tag_respecting_cooldown).to include(
          tag: "v2.7.0",
          commit_sha: "ee0669bd1cc54295c223e0bb666b733df41de1c5",
          version: Dependabot::GithubActions::Version.new("2.7.0")
        )
      end
    end

    context "when latest version tag is outside cooldown" do
      let(:dependency_name) { "actions/checkout" }
      let(:upload_pack_fixture) { "checkout" }
      let(:reference) { "v2" }
      let(:dependency_version) { "2" }
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "v2",
          branch: nil
        }
      end
      let(:finder) do
        described_class.new(
          dependency: dependency,
          dependency_files: [],
          credentials: github_credentials,
          security_advisories: security_advisories,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
        )
      end

      before do
        # Nothing is cooling down, so the shared cooldown returns the same tag
        # as the plain latest_version_tag.
        latest_tag = finder.latest_version_tag
        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:local_tag_for_latest_version)
          .and_return(latest_tag)
      end

      it "returns the same tag as latest_version_tag" do
        expect(latest_version_tag_respecting_cooldown).to eq(finder.latest_version_tag)
      end
    end

    context "when the selected release is a SHA" do
      before do
        allow(finder).to receive(:latest_release_version).and_return("deadbeef")
      end

      it "returns nil" do
        expect(latest_version_tag_respecting_cooldown).to be_nil
      end
    end
  end

  # Regression test for version tag prefix handling
  # Bug: Dependabot returns main branch commit instead of latest tag when
  # dependency refs like "0.0.13" don't match prefixed tags like "v0.0.13"
  describe "private repository with version tag prefixes" do
    let(:upload_pack_fixture) { "private-repo-with-version-prefixes" }
    let(:dependency_name) { "example-org/private-actions" }
    let(:reference) { "0.0.13" }
    let(:dependency_version) { "0.0.13" }

    let(:dependency_source) do
      {
        type: "git",
        url: "https://github.com/example-org/private-actions",
        ref: "0.0.13",
        branch: nil
      }
    end

    describe "#latest_release_version" do
      subject(:latest_release_version) { finder.latest_release_version }

      it "correctly identifies v0.0.24 as the latest version" do
        expect(latest_release_version).to eq(Dependabot::GithubActions::Version.new("0.0.24"))
        expect(latest_release_version).not_to eq("a9594b7a3de691e58c1ff7f96448d9b93fd831e7")
      end

      it "handles dependencies with version tag prefixes correctly" do
        # Regression test for issue where dependencies referencing "0.0.13"
        # were not considered pinned when the actual Git tag was "v0.0.13"
        package_details_fetcher = Dependabot::GithubActions::Package::PackageDetailsFetcher.new(
          dependency: dependency,
          credentials: [],
          ignored_versions: [],
          raise_on_ignored: false,
          security_advisories: []
        )

        git_commit_checker = package_details_fetcher.send(:git_commit_checker)

        # Dependency should be considered pinned even with version tag prefix mismatch
        expect(git_commit_checker.pinned?).to be(true)

        # PackageDetailsFetcher should return the latest version (not current commit)
        release_list = package_details_fetcher.release_list_for_git_dependency
        expect(release_list).to be_a(Dependabot::GithubActions::Version)
        expect(release_list.to_s).to eq("0.0.24")
      end
    end

    describe "#latest_version_tag" do
      subject(:latest_version_tag) { finder.latest_version_tag }

      it "returns tag information for v0.0.24" do
        expect(latest_version_tag).to include(
          tag: "v0.0.24",
          commit_sha: "b4cc9058ebd2336f73752f9d3c9b3835d52c66de",
          version: Dependabot::GithubActions::Version.new("0.0.24")
        )
      end
    end
  end

  describe "#commit_metadata_details" do
    subject(:commit_metadata_details) { finder.send(:commit_metadata_details) }

    let(:reference) { "v1" }
    let(:dependency_version) { "1.0.0" }

    let(:finder) do
      described_class.new(
        dependency: dependency,
        dependency_files: [],
        credentials: github_credentials,
        security_advisories: security_advisories,
        ignored_versions: ignored_versions,
        raise_on_ignored: raise_on_ignored,
        cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
      )
    end

    before do
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", upload_pack_fixture),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    context "when tag is an annotated tag" do
      it "uses tag creation date from for-each-ref instead of commit date" do
        tag_creation_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(finder).to receive_messages(
          latest_version_tag: { tag: "v1.0.0", version: Dependabot::GithubActions::Version.new("1.0.0"),
                                commit_sha: "abc123" },
          commit_ref: "abc123"
        )
        # No GitHub Release available — forces git fallback
        mock_client = instance_double(Octokit::Client, releases: [])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # for-each-ref returns the annotated tag date
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(tag_creation_date)

        expect(commit_metadata_details).to eq(tag_creation_date)
      end
    end

    context "when for-each-ref returns empty (lightweight tag not found)" do
      it "falls back to commit date from git show" do
        commit_date = "2026-06-01 10:00:00 +0000"

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(finder).to receive_messages(
          latest_version_tag: { tag: "v1.0.0", version: Dependabot::GithubActions::Version.new("1.0.0"),
                                commit_sha: "abc123" },
          commit_ref: "abc123"
        )
        # No GitHub Release available — forces git fallback
        mock_client = instance_double(Octokit::Client, releases: [])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        # for-each-ref returns empty
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return("")
        # Fallback to git show
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git show --no-patch/, hash_including(fingerprint: anything))
          .and_return(commit_date)

        expect(commit_metadata_details).to eq(commit_date)
      end
    end

    context "when tag points to old commit but was recently created" do
      it "uses tag creation date for cooldown (not old commit date)" do
        # Tag created today, but commit is from 30 days ago
        recent_tag_date = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S %z")

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(finder).to receive_messages(
          latest_version_tag: { tag: "v1.0.0", version: Dependabot::GithubActions::Version.new("1.0.0"),
                                commit_sha: "abc123" },
          commit_ref: "abc123"
        )
        # Stub GitHub releases to return empty (force git fallback)
        mock_client = instance_double(Octokit::Client, releases: [])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(recent_tag_date)

        expect(commit_metadata_details).to eq(recent_tag_date)
      end
    end

    context "when GitHub Release published_at is available" do
      it "uses published_at from Octokit instead of git clone" do
        published_at = Time.now.utc - (3 * 24 * 60 * 60)

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(finder).to receive(:latest_version_tag)
          .and_return({ tag: "v1.0.0", version: Dependabot::GithubActions::Version.new("1.0.0"),
                        commit_sha: "abc123" })

        sawyer_agent = instance_double(Sawyer::Agent)
        allow(sawyer_agent).to receive(:parse_links) { |value| [value, {}] }
        mock_release = Sawyer::Resource.new(
          sawyer_agent,
          { tag_name: "v1.0.0", published_at: published_at, prerelease: false }
        )
        mock_client = instance_double(Octokit::Client, releases: [mock_release])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        # Should NOT need to clone repo
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command).with(/git clone/)

        expect(commit_metadata_details).to eq(published_at.iso8601)
      end
    end

    context "when GitHub Release does not exist for the tag" do
      it "falls back to git for-each-ref" do
        tag_creation_date = (Time.now.utc - (8 * 24 * 60 * 60)).strftime("%Y-%m-%d %H:%M:%S %z")

        allow_any_instance_of(Dependabot::GitCommitChecker) # rubocop:disable RSpec/AnyInstance
          .to receive(:dependency_source_details)
          .and_return(source_details)
        allow(finder).to receive_messages(
          latest_version_tag: { tag: "v1.0.0", version: Dependabot::GithubActions::Version.new("1.0.0"),
                                commit_sha: "abc123" },
          commit_ref: "abc123"
        )

        # No release exists
        mock_client = instance_double(Octokit::Client, releases: [])
        allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

        # Falls back to git
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield("/tmp/fake")
        allow(Dir).to receive(:chdir).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git clone --bare/, any_args).and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(/git for-each-ref/, hash_including(fingerprint: anything))
          .and_return(tag_creation_date)

        expect(commit_metadata_details).to eq(tag_creation_date)
      end
    end
  end
end
