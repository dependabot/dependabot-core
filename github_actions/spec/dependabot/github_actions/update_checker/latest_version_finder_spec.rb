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
          allow(finder).to receive(:select_version_tags_in_cooldown_period) do |tags_with_dates|
            tags_with_dates.filter_map do |tag|
              tag_name = tag.is_a?(Hash) ? tag.fetch(:tag) : tag.tag
              tag_name if tag_name.start_with?("v3")
            end
          end
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
          allow(finder).to receive(:select_version_tags_in_cooldown_period).and_return([])
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

    describe "#select_version_tags_in_cooldown_period" do
      subject(:selected_tags) { finder.send(:select_version_tags_in_cooldown_period) }

      # Current time: 2024-04-03T16:00:00Z
      let(:current_time) { Time.parse("2024-04-03T16:00:00Z") }

      # Test fixtures: tags released at various dates
      let(:git_tags_with_dates) do
        [
          # Within 90-day cooldown (released ~60 days ago)
          Dependabot::GitTagWithDetail.new(tag: "v1.2.0", release_date: "2024-02-03T16:00:00Z"),
          # Within 90-day cooldown (released ~30 days ago)
          Dependabot::GitTagWithDetail.new(tag: "v1.1.5", release_date: "2024-03-04T16:00:00Z"),
          # Outside 90-day cooldown (released ~100 days ago)
          Dependabot::GitTagWithDetail.new(tag: "v1.1.0", release_date: "2023-12-25T16:00:00Z"),
          # Within 90-day cooldown (released ~5 days ago)
          Dependabot::GitTagWithDetail.new(tag: "v1.3.0", release_date: "2024-03-29T16:00:00Z")
        ]
      end

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
        allow(Time).to receive(:now).and_return(current_time)

        # Stub the package_details_fetcher to return our test data
        mock_fetcher = instance_double(Dependabot::GithubActions::Package::PackageDetailsFetcher)
        allow(mock_fetcher).to receive(:fetch_tag_and_release_date).and_return(git_tags_with_dates)
        allow(finder).to receive(:package_details_fetcher).and_return(mock_fetcher)
      end

      context "with 90-day cooldown enabled" do
        it "returns array of tag names" do
          expect(selected_tags).to be_an(Array)
          expect(selected_tags).to all(be_a(String))
        end

        it "includes only tags released within cooldown period" do
          # Tags released within 90 days: v1.2.0, v1.1.5, v1.3.0
          # Tags outside cooldown: v1.1.0 (released 100 days ago)
          expect(selected_tags).to include("v1.2.0", "v1.1.5", "v1.3.0")
          expect(selected_tags).not_to include("v1.1.0")
        end

        it "excludes tags outside cooldown period" do
          excluded_tags = selected_tags & ["v1.1.0"]
          expect(excluded_tags).to be_empty
        end

        it "returns all filtered tags in correct format" do
          expect(selected_tags.count).to eq(3)
          expect(selected_tags.sort).to eq(["v1.1.5", "v1.2.0", "v1.3.0"].sort)
        end
      end

      context "with 1-day cooldown" do
        let(:finder) do
          described_class.new(
            dependency: dependency,
            dependency_files: [],
            credentials: github_credentials,
            security_advisories: security_advisories,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 1)
          )
        end

        it "returns only tags released within 1 day" do
          # Only v1.3.0 (released ~5 days ago) should be excluded
          # Only v1.1.5 and v1.3.0 and v1.2.0 and v1.1.0 should ALL be checked
          # With 1-day cooldown: only v1.3.0 (5 days old) is outside
          # Actually v1.2.0 (60 days), v1.1.5 (30 days), v1.1.0 (100 days) are all outside
          # Only newly released tags within 1 day would be included
          expect(selected_tags).to be_empty
        end
      end

      context "when git fetch fails" do
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
          mock_fetcher = instance_double(Dependabot::GithubActions::Package::PackageDetailsFetcher)
          allow(mock_fetcher).to receive(:fetch_tag_and_release_date).and_raise(StandardError, "git error")
          allow(finder).to receive(:package_details_fetcher).and_return(mock_fetcher)
        end

        it "handles error gracefully and returns empty array" do
          expect(selected_tags).to eq([])
        end

        it "logs the error" do
          expect(Dependabot.logger).to receive(:error).with(/Error checking if version is in cooldown/)
          selected_tags
        end
      end

      context "when all tags are in cooldown" do
        let(:git_tags_with_dates) do
          [
            # All released recently
            Dependabot::GitTagWithDetail.new(tag: "v1.0.0", release_date: "2024-04-01T16:00:00Z"),
            Dependabot::GitTagWithDetail.new(tag: "v1.0.1", release_date: "2024-04-02T16:00:00Z")
          ]
        end

        it "returns all tags" do
          expect(selected_tags).to eq(["v1.0.0", "v1.0.1"])
        end
      end

      context "when no tags are in cooldown" do
        let(:git_tags_with_dates) do
          [
            # All released long ago
            Dependabot::GitTagWithDetail.new(tag: "v1.0.0", release_date: "2023-01-01T16:00:00Z"),
            Dependabot::GitTagWithDetail.new(tag: "v1.0.1", release_date: "2023-02-01T16:00:00Z")
          ]
        end

        it "returns empty array" do
          expect(selected_tags).to be_empty
        end
      end
    end
  end
end
