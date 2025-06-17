# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/package/package_details_fetcher"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/git_tag_with_detail"
require "excon"
RSpec.describe Dependabot::Terraform::Package::PackageDetailsFetcher do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/terraform-aws-modules/iam/aws",
      version: "1.0.0",
      package_manager: "terraform",
      requirements: [],
      previous_requirements: []
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
        { "tag_name" => "v1.0.0", "published_at" => "2023-01-01T00:00:00Z" },
        { "tag_name" => "v0.9.0", "published_at" => "2022-12-01T00:00:00Z" }
      ].to_json
    end

    before do
      allow(Excon).to receive(:get).and_return(instance_double(Excon::Response, status: 200, body: response_body))
    end

    it "fetches and parses release tags and dates" do
      result = fetcher.fetch_tag_and_release_date
      expect(result).to contain_exactly(
        have_attributes(tag: "v1.0.0", release_date: "2023-01-01T00:00:00Z"),
        have_attributes(tag: "v0.9.0", release_date: "2022-12-01T00:00:00Z")
      )
    end
  end

  describe "#fetch_tag_and_release_date_from_provider" do
    let(:response_body) do
      {
        "provider_versions" => [
          { "version" => "v1.0.0", "published_at" => "2023-01-01T00:00:00Z" },
          { "version" => "v0.9.0", "published_at" => "2022-12-01T00:00:00Z" }
        ]
      }.to_json
    end

    before do
      allow(Excon).to receive(:get).and_return(instance_double(Excon::Response, status: 200, body: response_body))
      allow(fetcher).to receive(:dependency_source_details).and_return({ module_identifier: "hashicorp/aws" })
    end

    it "fetches and parses provider release tags and dates" do
      result = fetcher.fetch_tag_and_release_date_from_provider
      expect(result).to contain_exactly(
        have_attributes(tag: "v1.0.0", release_date: "2023-01-01T00:00:00Z"),
        have_attributes(tag: "v0.9.0", release_date: "2022-12-01T00:00:00Z")
      )
    end
  end

  describe "#fetch_tag_and_release_date_from_module" do
    let(:response_body) do
      {
        "module-versions" => [
          { "version" => "v1.0.0", "published_at" => "2023-01-01T00:00:00Z" },
          { "version" => "v0.9.0", "published_at" => "2022-12-01T00:00:00Z" }
        ]
      }.to_json
    end

    before do
      allow(Excon).to receive(:get).and_return(instance_double(Excon::Response, status: 200, body: response_body))
      allow(fetcher).to receive(:dependency_source_details).and_return({ module_identifier:
        "terraform-aws-modules/iam/aws" })
    end

    it "fetches and parses module release tags and dates" do
      result = fetcher.fetch_tag_and_release_date_from_module
      expect(result).to contain_exactly(
        have_attributes(tag: "v1.0.0", release_date: "2023-01-01T00:00:00Z"),
        have_attributes(tag: "v0.9.0", release_date: "2022-12-01T00:00:00Z")
      )
    end
  end
end
