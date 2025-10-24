# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/opentofu/package/package_details_fetcher"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_commit_checker"
require "dependabot/git_tag_with_detail"
require "excon"
RSpec.describe Dependabot::Opentofu::Package::PackageDetailsFetcher do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "github.com/integrations/terraform-provider-github",
      version: "1.0.0",
      package_manager: "opentofu",
      requirements: [{
        requirement: "~> 6.6.0",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: "registry.opentofu.org",
          module_identifier: "hashicorp/aws"
        }
      }],
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
    it "fetches and parses release tags and dates", :vcr do
      result = fetcher.fetch_tag_and_release_date
      expect(result).to include(
        an_object_having_attributes(tag: "v6.5.0", release_date: "2025-01-17T01:19:11Z")
      )
    end
  end

  describe "#fetch_tag_and_release_date_from_provider" do
    it "fetches and parses provider release tags and dates", :vcr do
      result = fetcher.fetch_tag_and_release_date_from_provider
      expect(result).to include(
        an_object_having_attributes(tag: "v6.9.0", release_date: "2025-08-14T17:01:10Z")
      )
    end
  end

  describe "#fetch_tag_and_release_date_from_module" do
    # Create a new dependency for the module test since the dependency
    # on the class is not a module
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "github.com/integrations/terraform-provider-github",
        version: "1.0.0",
        package_manager: "opentofu",
        requirements: [{
          requirement: "~> 6.6.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.opentofu.org",
            module_identifier: "terraform-aws-modules/rds/aws"
          }
        }],
        previous_requirements: []
      )
    end

    it "fetches and parses module release tags and dates", :vcr do
      result = fetcher.fetch_tag_and_release_date_from_module
      expect(result).to include(
        an_object_having_attributes(tag: "v6.12.0", release_date: "2025-04-21T23:05:43Z")
      )
    end
  end
end
