# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/puppet/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Puppet::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "puppetlabs-dsc",
      version: "1.4.0",
      requirements: requirements,
      package_manager: "dep"
    )
  end
  let(:requirements) do
    [{
      file: "Puppetfile",
      requirement: "1.4.0",
      groups: [],
      source: dependency_source
    }]
  end
  let(:dependency_source) { nil }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "for a Puppet forge hosted module" do
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

      context "with GitHub details" do
        it { is_expected.to eq("https://github.com/puppetlabs/puppetlabs-dsc") }
      end

      context "without details" do
        let(:puppet_forge_response) do
          fixture("forge_responses", puppet_forge_fixture_name).
            gsub("github", "example")
        end

        it { is_expected.to be_nil }
      end

      context "for a subdependency" do
        let(:requirements) { [] }

        it { is_expected.to eq("https://github.com/puppetlabs/puppetlabs-dsc") }
      end
    end

    context "for a git source" do
      let(:puppet_forge_response) { nil }
      let(:dependency_source) do
        { type: "git", url: "https://github.com/puppetlabs/puppetlabs-dsc" }
      end

      it { is_expected.to eq("https://github.com/puppetlabs/puppetlabs-dsc") }

      context "that doesn't match a supported source" do
        let(:dependency_source) do
          { type: "git", url: "https://example.com/my_fork/bitflags" }
        end

        it { is_expected.to be_nil }
      end
    end
  end
end
