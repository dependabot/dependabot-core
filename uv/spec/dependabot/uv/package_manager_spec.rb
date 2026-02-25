# typed: false
# frozen_string_literal: true

require "dependabot/uv/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Uv::PackageManager do
  let(:package_manager) { described_class.new("0.6.2") }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(package_manager.version).to eq("0.6.2")
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq("uv")
      end
    end

    context "when pip-compile version extracted from pyenv is well formed" do
      # If this test starts failing, you need to adjust the "detect_pipenv_version" function
      # to return a valid version in format x.x, x.x.x etc. examples: 3.12.5, 3.12
      version = Dependabot::SharedHelpers.run_shell_command("pyenv exec pip-compile --version")
                                         .to_s.split("version ").last&.split(")")&.first

      it "does not raise error" do
        expect(version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end
  end
end
