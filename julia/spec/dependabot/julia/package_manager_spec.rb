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
          Dependabot::Version.new("1.0"),
          Dependabot::Version.new("1.6")
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
        expect { package_manager.version }
          .to raise_error("Failed to parse Julia version")
      end
    end
  end
end
