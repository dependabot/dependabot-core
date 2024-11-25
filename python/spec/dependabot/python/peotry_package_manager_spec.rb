# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Python::PeotryPackageManager do
  let(:package_manager) { described_class.new("1.8.3") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("1.8.3")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("poetry")
      end
    end

    context "when poetry version is extracted from pyenv is well formed" do
      # If this test starts failing, you need to adjust the "detect_poetry_version" function
      # to return a valid version in format x.x, x.x.x etc. examples: 3.12.5, 3.12
      version = Dependabot::SharedHelpers.run_shell_command("pyenv exec poetry --version")
                                         .split("version ").last&.split(")")&.first

      it "does not raise error" do
        expect(version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end
  end
end
