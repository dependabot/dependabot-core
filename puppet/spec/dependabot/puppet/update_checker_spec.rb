# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/puppet/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Puppet::UpdateChecker do
  it_behaves_like "an update checker"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "puppetlabs-dsc",
      version: "1.4.0",
      package_manager: "puppet",
      requirements: [{
        file: "Puppetfile",
        requirement: "1.4.0",
        source: { type: "default", source: "puppetlabs/dsc" },
        groups: []
      }]
    )
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Puppetfile",
        content: puppet_file_content
      )
    ]
  end
  let(:puppet_file_content) { %(mod "puppetlabs/dsc", '1.4.0') }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
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

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    let(:puppet_forge_url) do
      "https://forgeapi.puppet.com/v3/modules/puppetlabs-dsc"\
      "?exclude_fields=readme,license,changelog,reference"
    end

    before do
      stub_request(:get, puppet_forge_url).
        to_return(status: 200, body: puppet_forge_response)
    end
    let(:puppet_forge_response) do
      fixture("forge_responses", puppet_forge_fixture_name)
    end
    let(:puppet_forge_fixture_name) { "puppetlabs-dsc.json" }

    it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }

    it "proxies to LatestVersionFinder#latest_version class" do
      dummy_latest_version_finder =
        instance_double(
          described_class::LatestVersionFinder,
          latest_version: "latest"
        )

      expect(described_class::LatestVersionFinder).
        to receive(:new).
        with(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: []
        ).and_return(dummy_latest_version_finder)

      expect(checker.latest_version).to eq("latest")
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "just proxies to the #latest_version method" do
      allow(checker).to receive(:latest_version).and_return("latest")
      expect(checker.latest_resolvable_version).to eq("latest")
    end
  end
end
