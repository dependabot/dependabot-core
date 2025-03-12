# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/package_details"
require "dependabot/dependency"
require "dependabot/version"

RSpec.describe Dependabot::Package::PackageDetails do
  let(:dependency) do
    Dependabot::Dependency.new(name: "rails", version: "6.1.4", requirements: [], package_manager: "bundler")
  end
  let(:release1) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Version.new("6.1.4"),
      released_at: Time.parse("2023-01-01T12:00:00Z"),
      yanked: false,
      downloads: 1000,
      url: "https://rubygems.org/gems/rails-6.1.4.gem",
      package_type: "gem"
    )
  end
  let(:release2) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Version.new("6.0.3"),
      released_at: Time.parse("2022-01-01T12:00:00Z"),
      yanked: false,
      downloads: 500,
      url: "https://rubygems.org/gems/rails-6.0.3.gem",
      package_type: "gem"
    )
  end

  describe "#initialize" do
    it "creates a PackageDetails object with sorted releases" do
      details = described_class.new(dependency: dependency, releases: [release2, release1])

      expect(details.dependency).to eq(dependency)
      expect(details.releases.size).to eq(2)
      expect(details.releases.first).to eq(release1) # Should be the highest version first
      expect(details.releases.last).to eq(release2)  # Should be the lower version
    end

    it "handles empty releases array properly" do
      details = described_class.new(dependency: dependency, releases: [])

      expect(details.dependency).to eq(dependency)
      expect(details.releases).to be_empty
    end

    it "handles a single release" do
      details = described_class.new(dependency: dependency, releases: [release1])

      expect(details.dependency).to eq(dependency)
      expect(details.releases).to contain_exactly(release1)
    end
  end

  describe "#releases" do
    it "returns releases sorted in descending order" do
      details = described_class.new(dependency: dependency, releases: [release2, release1])

      expect(details.releases.map(&:version)).to eq([
        Dependabot::Version.new("6.1.4"),
        Dependabot::Version.new("6.0.3")
      ])
    end
  end
end
