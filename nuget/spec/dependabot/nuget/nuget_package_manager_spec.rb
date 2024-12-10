# typed: false
# frozen_string_literal: true

require "dependabot/nuget/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Nuget::NugetPackageManager do
  let(:package_manager) { described_class.new("6.5.0") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("6.5.0")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("nuget")
      end
    end

    context "when nuget version extracted is well formed" do
      # If this test starts failing, you need to adjust the "nuget_version" function
      # to return a valid version in format x.x, x.x.x etc. examples: 3.12.5, 3.12 along with
      # following block
      version = Dependabot::SharedHelpers.run_shell_command("dotnet nuget --version").split("Command Line").last&.strip

      it "does not raise error" do
        expect(version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end
  end
end
