# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/cooldown_date_tracker"

RSpec.describe Dependabot::Package::CooldownDateTracker do
  subject(:tracker) { described_class.new(dependency: dependency, ignored_versions: []) }

  let(:dependency) do
    Dependabot::Dependency.new(name: "dummy", version: "1.0.0", requirements: [], package_manager: "dummy")
  end
  let(:release) do
    Dependabot::Package::PackageRelease.new(version: TestVersion.new("2.0.0"), released_at: Time.utc(2023, 1, 1))
  end
  let(:releases) { [release] }

  describe "#filter" do
    context "when no undated cooldown candidates are recorded" do
      it "returns the selected releases without marking the dependency" do
        expect(tracker.filter(language_version: nil, requirements: false) { releases }).to equal(releases)
        expect(dependency.metadata[:cooldown_date_unavailable]).to be_nil
      end

      it "does not recheck release eligibility" do
        allow(release).to receive(:yanked?).and_call_original

        tracker.filter(language_version: nil, requirements: false) { releases }

        expect(release).not_to have_received(:yanked?)
      end
    end
  end
end
