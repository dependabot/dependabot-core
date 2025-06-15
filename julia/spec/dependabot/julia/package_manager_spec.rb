# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/package_manager"

RSpec.describe Dependabot::Julia::PackageManager do
  describe "#ecosystem" do
    subject(:package_manager) { described_class.new }

    let(:expected_minimum_version) { Dependabot::Julia::PackageManager::MINIMUM_VERSION }
    let(:expected_current_version) { Dependabot::Julia::PackageManager::CURRENT_VERSION }

    before do
      # Mock version detection to return consistent test values
      allow(described_class).to receive(:detected_version).and_return(expected_minimum_version)
    end

    it "returns correct ecosystem details with defined version" do
      expect(package_manager.name).to eq("julia")
      # The version will be the MINIMUM_VERSION from the PackageManager
      expect(package_manager.version).to eq(Dependabot::Version.new(expected_minimum_version))
      expect(package_manager.supported_versions)
        .to contain_exactly(
          Dependabot::Version.new(expected_minimum_version),
          Dependabot::Version.new(expected_current_version)
        )
      expect(package_manager.deprecated_versions).to be_empty
    end

    context "when Julia version detection is configured" do
      # This context might need to be re-evaluated.
      # If `self.class.detected_version` returns a fixed string,
      # the error conditions it previously tested might not be reachable in the same way.

      before do
        # Stub the class method directly if it's the one being called by `new`
        allow(described_class)
          .to receive(:detected_version)
          .and_return(expected_minimum_version) # Ensure it returns a valid version string
      end

      it "initializes with the configured version" do
        # TODO: If PackageManager.new could fail due to version detection,
        # test that behavior. For now, it uses a configured version.
        expect { package_manager.version }.not_to raise_error
        expect(package_manager.version).to eq(Dependabot::Version.new(expected_minimum_version))
      end

      context "when version detection is forced to fail" do
        before do
          allow(described_class)
            .to receive(:detected_version)
            .and_raise("Failed to parse Julia version")
        end

        it "raises an error during initialization" do
          # TODO: The PackageManager's initialize method catches errors from detected_version
          # and potentially raises its own or uses a default.
          # This test needs to align with that behavior.
          # If it's designed to not raise from `new()`, this test should change.
          # Based on current PackageManager, it might raise from `super` if `detected_version` is nil.
          # The PackageManager now has its own `detected_version` that returns MINIMUM_VERSION
          # or raises.
          expect { described_class.new }
            .to raise_error("Failed to parse Julia version")
        end
      end
    end
  end
end
