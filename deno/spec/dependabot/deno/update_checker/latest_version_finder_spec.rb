# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/update_checker/latest_version_finder"

RSpec.describe Dependabot::Deno::UpdateChecker::LatestVersionFinder do
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
      name: "@std/path",
      version: "1.0.0",
      requirements: [],
      package_manager: "deno"
    )
  end
  let(:release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Deno::Version.new("1.1.0"),
      released_at: nil
    )
  end
  let(:package_details_fetcher) do
    instance_double(
      Dependabot::Deno::Package::PackageDetailsFetcher,
      available_versions: [release]
    )
  end

  before do
    allow(Dependabot::Deno::Package::PackageDetailsFetcher)
      .to receive(:new).with(dependency: dependency).and_return(package_details_fetcher)
  end

  it "allows the release and marks the dependency when its date is unavailable" do
    expect(latest_version).to eq(Dependabot::Deno::Version.new("1.1.0"))
    expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
  end
end
