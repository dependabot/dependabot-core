# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Python::PipPackageManager do
  let(:package_manager) { described_class.new("24.0") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("24.0")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("pip")
      end
    end

    context "when pip version is extracted from pyenv is well formed" do
      # If this test start failing, you need to adjust the "detect_poetry_version" function
      # to return a valid version in format x.x, x.x.x etc. examples: 3.12.5, 3.12
      version = Dependabot::SharedHelpers.run_shell_command("pyenv exec pip -V")
                                         .split("from").first&.split("pip")&.last&.strip.to_s

      it "does not raise error" do
        expect(version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end
  end
end
