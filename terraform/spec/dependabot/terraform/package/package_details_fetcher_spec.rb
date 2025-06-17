# typed: false
# frozen_string_literal: true

require "dependabot/swift/package/package_details_fetcher"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/git_tag_with_detail"
require "excon"

RSpec.describe Dependabot::Terraform::Package::PackageDetailsFetcher do
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
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: [],
      raise_on_ignored: false,
      consider_version_branches_pinned: true
    )
  end
  let(:fetcher) do
    described_class.new(dependency: dependency, credentials: credentials, git_commit_checker: git_commit_checker)
  end

  describe "#fetch_tag_and_release_date" do
    let(:response_body) do
      [
        { "tag_name" => "v1.0.0", "published_at" => "2025-05-27T12:34:56Z" },
        { "tag_name" => "v2.0.0", "published_at" => "2025-05-28T12:34:56Z" }
      ].to_json
    end

    before do
      allow(Excon).to receive(:get).and_return(instance_double(Excon::Response, status: 200, body: response_body))
    end

    it "removes 'github.com/' from the dependency name" do
      truncate_github_url = dependency.name.gsub("github.com/", "")
      expect(truncate_github_url).to eq("patrick-zippenfenig/SwiftNetCDF")
    end

    it "fetches and parses release details from the GitHub API" do
      result = fetcher.fetch_tag_and_release_date
      expect(result.map(&:tag)).to eq(["v2.0.0", "v1.0.0"]) # Sorted in descending order
      expect(result.map(&:release_date)).to eq(["2025-05-28T12:34:56Z", "2025-05-27T12:34:56Z"])
    end

    context "when the API call fails" do
      before do
        allow(Excon).to receive(:get).and_return(instance_double(Excon::Response, status: 500, body: "Error"))
      end

      it "returns an empty array and logs an error" do
        expect(Dependabot.logger).to receive(:error).with("Failed call details: Error")
        result = fetcher.fetch_tag_and_release_date
        expect(result).to eq([])
      end
    end
  end
end
