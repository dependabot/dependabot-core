# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/update_checker/latest_version_finder"

RSpec.describe Dependabot::Nix::UpdateChecker::LatestVersionFinder do
  subject(:latest_version) { finder.latest_version }

  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: [],
      security_advisories: [],
      raise_on_ignored: false,
      cooldown_options: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "0.0.0-0.1",
      requirements: [],
      package_manager: "nix"
    )
  end
  let(:release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Nix::Version.new("0.0.0-0.2"),
      released_at: nil,
      tag: "new-revision"
    )
  end
  let(:package_details_fetcher) do
    instance_double(
      Dependabot::Nix::Package::PackageDetailsFetcher,
      available_versions: [release]
    )
  end

  before do
    allow(Dependabot::Nix::Package::PackageDetailsFetcher)
      .to receive(:new).and_return(package_details_fetcher)
  end

  it "allows the release and marks the dependency when its date is unavailable" do
    expect(latest_version).to eq(Dependabot::Nix::Version.new("0.0.0-0.2"))
    expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
  end
end
