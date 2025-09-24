# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/update_checker/latest_version_finder"

namespace = Dependabot::Hex::UpdateChecker
RSpec.describe namespace::LatestVersionFinder do
  before do
    stub_request(:get, hex_url).to_return(status: 200, body: hex_response)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: [],
      cooldown_options: update_cooldown
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end
  let(:dependency_name) { "plug" }
  let(:version) { "1.3.0" }
  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end
  let(:dependency_files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(content: mixfile_body, name: "mix.exs")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "mix.lock")
  end
  let(:mixfile_body) { fixture("mixfiles", "minor_version") }
  let(:lockfile_body) { fixture("lockfiles", "minor_version") }
  let(:hex_url) { "https://hex.pm/api/packages/#{dependency_name}" }
  let(:hex_response) do
    fixture("registry_api", "#{dependency_name}_response.json")
  end
  let(:update_cooldown) { nil }

  describe "#latest_version" do
    subject(:latest_version) { checker.release_version }

    it { is_expected.to eq(Gem::Version.new("1.7.1")) }

    context "without a lockfile" do
      let(:files) { [mixfile] }

      it { is_expected.to eq(Gem::Version.new("1.7.1")) }

      context "with a requirement specified to 2dp" do
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: "~> 1.3", groups: [], source: nil }]
        end
        let(:mixfile_body) { fixture("mixfiles", "major_version") }

        it { is_expected.to eq(Gem::Version.new("1.7.1")) }
      end
    end
  end
end
