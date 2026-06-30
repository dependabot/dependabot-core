# typed: false
# frozen_string_literal: true

require "dependabot/swift/package/package_details_fetcher"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_tag_with_detail"
require "dependabot/source"
require "dependabot/clients/github_with_retries"

RSpec.describe Dependabot::Swift::Package::PackageDetailsFetcher do
  def release_stub(tag_name:, published_at:, prerelease:)
    Struct.new(:tag_name, :published_at, :prerelease)
          .new(tag_name, published_at, prerelease)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/patrick-zippenfenig/SwiftNetCDF",
      version: "v1.1.7",
      requirements: [],
      package_manager: "swift"
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        type: "git_source",
        host: "github.com",
        username: "test-user",
        password: "test-password"
      )
    ]
  end

  let(:fetcher) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#fetch_tag_and_release_date" do
    let(:github_client) { double("GithubWithRetries") } # rubocop:disable RSpec/VerifiedDoubles

    let(:releases) do
      [
        release_stub(tag_name: "v1.0.0", published_at: Time.parse("2025-05-27T12:34:56Z"), prerelease: false),
        release_stub(tag_name: "v2.0.0", published_at: Time.parse("2025-05-28T12:34:56Z"), prerelease: false)
      ]
    end

    before do
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(github_client)
      allow(github_client).to receive(:releases).and_return(releases)
    end

    it "fetches and parses release details" do
      result = fetcher.fetch_tag_and_release_date
      expect(result.map(&:tag)).to eq(["v2.0.0", "v1.0.0"])
    end

    it "sorts by semantic version in descending order" do
      result = fetcher.fetch_tag_and_release_date
      expect(result.first.tag).to eq("v2.0.0")
      expect(result.last.tag).to eq("v1.0.0")
    end

    context "when releases include prereleases" do
      let(:releases) do
        [
          release_stub(tag_name: "v1.0.0", published_at: Time.parse("2025-05-27T12:34:56Z"), prerelease: false),
          release_stub(
            tag_name: "v2.0.0-beta.1",
            published_at: Time.parse("2025-05-28T12:34:56Z"),
            prerelease: true
          ),
          release_stub(tag_name: "v2.0.0", published_at: Time.parse("2025-05-29T12:34:56Z"), prerelease: false)
        ]
      end

      it "excludes prerelease versions" do
        result = fetcher.fetch_tag_and_release_date
        tags = result.map(&:tag)
        expect(tags).to eq(["v2.0.0", "v1.0.0"])
        expect(tags).not_to include("v2.0.0-beta.1")
      end
    end

    context "when releases include non-version tags" do
      let(:releases) do
        [
          release_stub(tag_name: "v1.0.0", published_at: Time.parse("2025-05-27T12:34:56Z"), prerelease: false),
          release_stub(
            tag_name: "nightly-2025-05-28",
            published_at: Time.parse("2025-05-28T12:34:56Z"),
            prerelease: false
          )
        ]
      end

      it "excludes non-version tags" do
        result = fetcher.fetch_tag_and_release_date
        expect(result.map(&:tag)).to eq(["v1.0.0"])
      end
    end

    context "when releases include draft releases without tag_name" do
      let(:releases) do
        [
          release_stub(tag_name: nil, published_at: Time.parse("2025-05-27T12:34:56Z"), prerelease: false),
          release_stub(tag_name: "v1.0.0", published_at: Time.parse("2025-05-28T12:34:56Z"), prerelease: false)
        ]
      end

      it "skips releases without a tag name" do
        result = fetcher.fetch_tag_and_release_date
        expect(result.map(&:tag)).to eq(["v1.0.0"])
      end
    end

    context "when the API call fails" do
      before do
        allow(github_client).to receive(:releases).and_raise(Octokit::Error)
      end

      it "returns an empty array and logs a debug message" do
        expect(Dependabot.logger).to receive(:debug).with(/Error fetching release details/)
        result = fetcher.fetch_tag_and_release_date
        expect(result).to eq([])
      end
    end

    context "when dependency is not on GitHub" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "gitlab.com/someuser/somerepo",
          version: "1.0.0",
          requirements: [],
          package_manager: "swift"
        )
      end

      it "returns an empty array" do
        result = fetcher.fetch_tag_and_release_date
        expect(result).to eq([])
      end
    end
  end
end
