# typed: false
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/git_submodules"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

RSpec.describe Dependabot::GitSubmodules::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "git_submodules"
    )
  end

  let(:requirements) { [] }
  let(:dependency_name) { "example" }
  let(:dependency_version) { "1.0.0" }

  let(:credentials) { [] }

  describe "#available_versions" do
    it "returns the head commit for the current branch" do
      allow_any_instance_of(Dependabot::GitCommitChecker).to receive(:head_commit_for_current_branch) # rubocop:disable RSpec/AnyInstance
        .and_return("42bfb4554167e1d2fc2b950728d9bd8164f806c1")

      expect(fetcher.available_versions).to eq("42bfb4554167e1d2fc2b950728d9bd8164f806c1")
    end
  end
end
