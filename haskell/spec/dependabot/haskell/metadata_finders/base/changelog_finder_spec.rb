# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/haskell/metadata_finders/base/changelog_finder"

RSpec.describe Dependabot::Haskell::MetadataFinders::Base::ChangelogFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      credentials: credentials,
      dependency: dependency
    )
  end
  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      previous_version: dependency_previous_version,
      package_manager: package_manager
    )
  end
  let(:package_manager) { "bundler" }
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_version) { "1.0.0" }

  describe "#major_version_upgrade?" do
    subject { finder.major_version_upgrade? }

    describe "PVP regards the difference between 1.4.0 and 1.0.0 as major" do
      it { is_expected.to eq(true) }
    end
  
  end
end
