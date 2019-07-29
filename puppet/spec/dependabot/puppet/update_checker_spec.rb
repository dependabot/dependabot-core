# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/puppet/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Puppet::UpdateChecker, :vcr do
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
        groups: [],
      }],
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

  let(:puppet_file_content) do
    <<~PUPMOD
      mod "puppetlabs/dsc", '1.4.0'
    PUPMOD
  end

  let(:ignored_versions) { [] }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      ignored_versions: ignored_versions
    )
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "updates semver versions" do
      expect(latest_resolvable_version).
        to eq(Dependabot::Puppet::Version.new("1.9.2"))
    end
  end
end
