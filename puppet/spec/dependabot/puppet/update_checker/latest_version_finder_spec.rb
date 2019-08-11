# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/puppet/update_checker/latest_version_finder"

RSpec.describe Dependabot::Puppet::UpdateChecker::LatestVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "puppet"
    )
  end
  let(:dependency_name) { "puppetlabs-dsc" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{
      file: "Puppetfile",
      requirement: "1.4.0",
      source: nil,
      groups: []
    }]
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
  let(:security_advisories) { [] }

  before do
    stub_request(:get, puppet_forge_url).
      to_return(status: 200, body: puppet_forge_response)
  end
  let(:puppet_forge_url) do
    "https://forgeapi.puppet.com/v3/modules/puppetlabs-dsc"\
    "?exclude_fields=readme,license,changelog,reference"
  end
  let(:puppet_forge_response) do
    fixture("forge_responses", puppet_forge_fixture_name)
  end
  let(:puppet_forge_fixture_name) { "puppetlabs-dsc.json" }

  describe "#latest_version" do
    subject { finder.latest_version }
    it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }

    context "when the puppet forge link resolves to a redirect" do
      let(:redirect_url) do
        "https://forgeapi.puppet.com/v3/modules/PuppetLabs-dsc"\
        "?exclude_fields=readme,license,changelog,reference"
      end

      before do
        stub_request(:get, puppet_forge_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: puppet_forge_response)
      end

      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }
    end

    context "when the puppet forge link fails at first" do
      before do
        stub_request(:get, puppet_forge_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: puppet_forge_response)
      end

      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }
    end

    context "when the pypi link resolves to a 'Not Found' page" do
      let(:puppet_forge_fixture_name) { "not_found.json" }
      it { is_expected.to be_nil }
    end

    context "when the latest versions have been yanked" do
      let(:puppet_forge_fixture_name) { "puppetlabs-dsc-yanked.json" }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.1")) }
    end

    context "when the user's current version is a pre-release" do
      let(:dependency_version) { "2.0.0-alpha" }
      let(:dependency_requirements) do
        [{
          file: "Puppetfile",
          requirement: "2.0.0-alpha",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to eq(Dependabot::Puppet::Version.new("2.0.0-beta")) }
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.9.0, < 2.0"] }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.8.0")) }
    end

    context "and the current requirement has a pre-release requirement" do
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "Puppetfile",
          requirement: ">=2.0.0-alpha",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to eq(Dependabot::Puppet::Version.new("2.0.0-beta")) }
    end
  end

  describe "#latest_version_with_no_unlock" do
    subject { finder.latest_version_with_no_unlock }

    let(:dependency_requirements) do
      [{ file: "req.txt", requirement: req_string, groups: [], source: nil }]
    end

    context "with no requirement" do
      let(:req_string) { nil }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 1.9.0.a, < 2.0"] }
        it { is_expected.to eq(Dependabot::Puppet::Version.new("1.8.0")) }
      end

      context "when the latest versions have been yanked" do
        let(:puppet_forge_fixture_name) { "puppetlabs-dsc-yanked.json" }
        it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.1")) }
      end
    end

    context "with an equality string" do
      let(:req_string) { "1.8.0" }
      let(:dependency_version) { "1.8.0" }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.8.0")) }
    end

    context "with a >= string" do
      let(:req_string) { ">=1.8.0" }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.2")) }
    end

    context "with a full range string" do
      let(:req_string) { ">=1.0.0,<1.9.0" }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.8.0")) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    let(:dependency_version) { "1.8.0" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "puppet",
          vulnerable_versions: ["<= 1.8.0"]
        )
      ]
    end
    it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.0")) }

    context "when the lowest version has been yanked" do
      let(:puppet_forge_fixture_name) { "puppetlabs-dsc-yanked.json" }
      it { is_expected.to eq(Dependabot::Puppet::Version.new("1.9.1")) }
    end
  end
end
