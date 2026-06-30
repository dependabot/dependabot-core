# typed: false
# frozen_string_literal: true

require "dependabot/swift/update_checker/latest_version_resolver"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/package/release_cooldown_options"
require "dependabot/swift/package/package_details_fetcher"

RSpec.describe Dependabot::Swift::UpdateChecker::LatestVersionResolver do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/patrick-zippenfenig/SwiftNetCDF",
      version: "1.1.7",
      requirements: [],
      package_manager: "swift"
    )
  end

  let(:credentials) { [Dependabot::Credential.new(type: "git_source", host: "github.com", password: "test-token")] }
  let(:git_commit_checker) do
    instance_double(Dependabot::GitCommitChecker)
  end
  let(:package_details_fetcher) do
    instance_double(Dependabot::Swift::Package::PackageDetailsFetcher)
  end
  let(:cooldown_options) do
    Dependabot::Package::ReleaseCooldownOptions.new(
      default_days: 30,
      semver_major_days: 60,
      semver_minor_days: 45,
      semver_patch_days: 15
    )
  end

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      cooldown_options: cooldown_options,
      git_commit_checker: git_commit_checker
    )
  end

  describe "#latest_version_tag" do
    let(:latest_tag) do
      { tag: "v2.0.0", version: Dependabot::Swift::Version.new("2.0.0"), commit_sha: "abc124" }
    end

    context "when cooldown is not active" do
      let(:cooldown_options) { nil }

      it "returns the latest version tag from git_commit_checker" do
        allow(git_commit_checker).to receive(:local_tag_for_latest_version).and_return(latest_tag)
        expect(resolver.latest_version_tag).to eq(latest_tag)
      end
    end

    context "when cooldown is active but no tags are in cooldown" do
      let(:allowed_tags) do
        [
          instance_double(Dependabot::GitRef, name: "v1.2.0"),
          instance_double(Dependabot::GitRef, name: "v2.0.0")
        ]
      end

      before do
        allow(git_commit_checker).to receive(:allowed_version_tags).and_return(allowed_tags)
        allow(git_commit_checker).to receive(:max_local_tag).with(allowed_tags).and_return(latest_tag)
        allow(resolver).to receive(:package_details_fetcher).and_return(package_details_fetcher)
        allow(package_details_fetcher).to receive(:fetch_tag_and_release_date).and_return([])
      end

      it "returns the latest allowed tag" do
        expect(resolver.latest_version_tag).to eq(latest_tag)
      end
    end

    context "when a tag is in cooldown" do
      let(:v1_tag) { instance_double(Dependabot::GitRef, name: "v1.2.0") }
      let(:v2_tag) { instance_double(Dependabot::GitRef, name: "v2.0.0") }
      let(:allowed_tags) { [v1_tag, v2_tag] }
      let(:filtered_tag) do
        { tag: "v1.2.0", version: Dependabot::Swift::Version.new("1.2.0"), commit_sha: "abc123" }
      end

      before do
        allow(git_commit_checker).to receive_messages(
          allowed_version_tags: allowed_tags,
          max_local_tag: filtered_tag
        )
        allow(resolver).to receive(:package_details_fetcher).and_return(package_details_fetcher)

        recent_release = Dependabot::GitTagWithDetail.new(
          tag: "v2.0.0",
          release_date: (Time.now - 60).iso8601 # 1 minute ago — within cooldown
        )
        allow(package_details_fetcher).to receive(:fetch_tag_and_release_date).and_return([recent_release])
      end

      it "filters out the tag in cooldown period" do
        result = resolver.latest_version_tag
        expect(result).to eq(filtered_tag)
      end
    end
  end

  describe "skip_cooldown?" do
    context "when cooldown_options is nil" do
      let(:cooldown_options) { nil }

      it "skips cooldown" do
        allow(git_commit_checker).to receive(:local_tag_for_latest_version).and_return(
          { tag: "v1.0.0", version: Dependabot::Swift::Version.new("1.0.0"), commit_sha: "abc" }
        )
        # Should go directly to local_tag_for_latest_version without fetching releases
        result = resolver.latest_version_tag
        expect(result).not_to be_nil
        expect(git_commit_checker).to have_received(:local_tag_for_latest_version)
      end
    end

    context "when all cooldown days are zero" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 0,
          semver_major_days: 0,
          semver_minor_days: 0,
          semver_patch_days: 0
        )
      end

      it "skips cooldown" do
        allow(git_commit_checker).to receive(:local_tag_for_latest_version).and_return(
          { tag: "v1.0.0", version: Dependabot::Swift::Version.new("1.0.0"), commit_sha: "abc" }
        )
        resolver.latest_version_tag
        expect(git_commit_checker).to have_received(:local_tag_for_latest_version)
      end
    end
  end

  describe "version_in_cooldown?" do
    before do
      allow(Time).to receive(:now).and_return(Time.parse("2025-08-08T17:30:00.000Z"))
    end

    context "when tag has no release date" do
      it "returns false via latest_version_tag (tag not filtered)" do
        tag_without_date = Dependabot::GitTagWithDetail.new(tag: "v1.2.0", release_date: nil)
        v1_ref = instance_double(Dependabot::GitRef, name: "v1.2.0")
        allowed_tags = [v1_ref]

        allow(git_commit_checker).to receive(:allowed_version_tags).and_return(allowed_tags)
        allow(git_commit_checker).to receive(:max_local_tag).with(allowed_tags).and_return(
          { tag: "v1.2.0", version: Dependabot::Swift::Version.new("1.2.0"), commit_sha: "abc" }
        )
        allow(resolver).to receive(:package_details_fetcher).and_return(package_details_fetcher)
        allow(package_details_fetcher).to receive(:fetch_tag_and_release_date).and_return([tag_without_date])

        result = resolver.latest_version_tag
        # Tag should NOT be filtered (no date = not in cooldown)
        expect(result[:version]).to eq(Dependabot::Swift::Version.new("1.2.0"))
      end
    end

    context "when release is outside cooldown period" do
      it "does not filter the tag" do
        # Release was 90 days ago, cooldown is 60 days for major
        old_release = Dependabot::GitTagWithDetail.new(
          tag: "v2.0.0",
          release_date: (Time.parse("2025-08-08T17:30:00.000Z") - (90 * 24 * 60 * 60)).iso8601
        )
        v2_ref = instance_double(Dependabot::GitRef, name: "v2.0.0")
        allowed_tags = [v2_ref]

        allow(git_commit_checker).to receive(:allowed_version_tags).and_return(allowed_tags)
        allow(git_commit_checker).to receive(:max_local_tag).with(allowed_tags).and_return(
          { tag: "v2.0.0", version: Dependabot::Swift::Version.new("2.0.0"), commit_sha: "abc" }
        )
        allow(resolver).to receive(:package_details_fetcher).and_return(package_details_fetcher)
        allow(package_details_fetcher).to receive(:fetch_tag_and_release_date).and_return([old_release])

        result = resolver.latest_version_tag
        expect(result[:version]).to eq(Dependabot::Swift::Version.new("2.0.0"))
      end
    end
  end
end
