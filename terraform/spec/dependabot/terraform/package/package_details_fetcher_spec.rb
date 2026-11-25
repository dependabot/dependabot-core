# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/package/package_details_fetcher"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/git_tag_with_detail"
require "excon"
RSpec.describe Dependabot::Terraform::Package::PackageDetailsFetcher do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/terraform-aws-modules/iam/aws",
      version: "1.0.0",
      package_manager: "terraform",
      requirements: [],
      previous_requirements: []
    )
  end

  sig { returns(T::Array[Dependabot::Credential]) }
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
  sig { returns(Dependabot::GitCommitChecker) }
  let(:git_commit_checker) do
    Dependabot::GitCommitChecker.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: [],
      raise_on_ignored: false,
      consider_version_branches_pinned: true
    )
  end
  sig { returns(Dependabot::Terraform::Package::PackageDetailsFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:fetcher) do
    described_class.new(dependency: dependency, credentials: credentials, git_commit_checker: git_commit_checker)
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#fetch_tag_and_release_date_from_provider" do
    sig { returns(String) }
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
    end

    it "fetches and parses provider release tags and dates since identifier is passed nil" do
      result = fetcher.fetch_tag_and_release_date_from_provider
      expect(result).to be_empty
    end
  end

  describe "#fetch_tag_and_release_date_from_module" do
    sig { returns(String) }
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
    end

    it "fetches and parses module release tags and dates since identifier is passed nil" do
      result = fetcher.fetch_tag_and_release_date_from_module
      expect(result).to be_empty
    end
  end

  context "with a registry dependency whose registry returns an unparseable response" do
    sig { returns(Dependabot::Dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "hashicorp/aws",
        version: "1.0.0",
        package_manager: "terraform",
        requirements: [{
          requirement: "1.0.0",
          groups: [],
          file: "main.tf",
          source: { type: "provider", registry_hostname: "registry.terraform.io", module_identifier: "hashicorp/aws" }
        }]
      )
    end

    before do
      stub_request(:get, "https://registry.terraform.io/v2/providers/hashicorp/aws?include=provider-versions")
        .to_return(status: 200, body: "")
    end

    it "attaches only the registry host to the parse error" do
      expect { fetcher.fetch_tag_and_release_date_from_provider }.to raise_error(JSON::ParserError) do |error|
        context = T.must(Dependabot::ErrorReportContext.build(error: error))
        expect(context).to include("host" => "registry.terraform.io", "http-method" => "GET")
        expect(context.values.join).not_to include("/v2/providers")
      end
    end
  end
end
