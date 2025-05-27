# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/julia/package_manager"

RSpec.describe Dependabot::Julia::PackageManager do
  describe "#ecosystem" do
    subject(:package_manager) { described_class.new }

    it "returns correct ecosystem details" do
      expect(package_manager.name).to eq("julia")
      expect(package_manager.version).to be_a(Dependabot::Version)
      expect(package_manager.supported_versions)
        .to contain_exactly(
          Dependabot::Version.new(Dependabot::Julia::PackageManager::MINIMUM_VERSION),
          Dependabot::Version.new(Dependabot::Julia::PackageManager::CURRENT_VERSION)
        )
      expect(package_manager.deprecated_versions).to be_empty
    end

    context "when Julia is not available" do
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command)
          .and_raise(StandardError)
      end

      it "raises helpful error" do
        expect { package_manager.version } # This will trigger initialization if not already done,
                                          # or directly call instance methods that use run_shell_command.
                                          # The error should come from the instance's detected_version.
          .to raise_error("Failed to parse Julia version")
      end

      # Add a test for the initialization itself if self.class.detected_version is the one failing first
      it "raises helpful error on initialization if class method fails" do
        # This test assumes the stub causes self.class.detected_version to fail
        # and that this failure is translated by PackageManager.new or its call chain.
        # If PackageManager.new directly raises StandardError, this test needs adjustment.
        # The fix in package_manager.rb (self.class.detected_version) should make this pass.
        expect { described_class.new }
          .to raise_error("Failed to parse Julia version")
      end
    end
  end
end
