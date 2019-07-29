# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/puppet/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Puppet::MetadataFinder, :vcr do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "puppetlabs-dsc",
      version: "1.4.0",
      requirements: [{
        file: "Puppetfile",
        requirement: "1.4.0",
        groups: [],
        source: {
          type: "default",
          source: "puppetlabs/dsc"
        }
      }],
      package_manager: "dep"
    )
  end
  let(:source) { nil }
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

    context "with no requirements (i.e., a subdependency)" do
      let(:requirements) { [] }

      it { is_expected.to eq("https://github.com/puppetlabs/puppetlabs-dsc") }

      context "for a forge project" do
        let(:dependency_name) { "puppetlabs-dsc" }
        it { is_expected.to eq("https://github.com/puppetlabs/puppetlabs-dsc") }
      end
    end
  end
end
