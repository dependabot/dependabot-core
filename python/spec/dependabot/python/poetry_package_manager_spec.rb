# typed: false
# frozen_string_literal: true

require "dependabot/python/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Python::PoetryPackageManager do
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

    context "when a requirement is provided" do
      let(:requirement) { Dependabot::Python::Requirement.new(">= 1.0") }
      let(:package_manager) { described_class.new("1.8.3", requirement) }

      it "stores the requirement" do
        expect(package_manager.requirement).to eq(requirement)
      end
    end

    context "when poetry version extracted from pyenv is well formed" do
      # If this test starts failing, you need to adjust the "detect_poetry_version" function
      # to return a valid version in format x.x, x.x.x etc. examples: 3.12.5, 3.12
      let(:version) do
        Dependabot::SharedHelpers.run_shell_command("pyenv exec poetry --version")
                                 .split("version ").last&.split(")")&.first
      end

      it "does not raise error" do
        expect(version.match(/^\d+(?:\.\d+)*$/)).to be_truthy
      end
    end
  end

  describe "#raise_if_unsupported!" do
    context "when no requirement is set" do
      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end

    context "when the installed version satisfies the requirement" do
      let(:requirement) { Dependabot::Python::Requirement.new(">= 1.0") }
      let(:package_manager) { described_class.new("1.8.3", requirement) }

      it "does not raise an error" do
        expect { package_manager.raise_if_unsupported! }.not_to raise_error
      end
    end

    context "when the installed version does not satisfy the requirement" do
      let(:requirement) { Dependabot::Python::Requirement.new(">= 3.0") }
      let(:package_manager) { described_class.new("2.2.1", requirement) }

      it "raises ToolVersionNotSupported" do
        expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported) do |error|
          expect(error.tool_name).to eq("poetry")
          expect(error.detected_version).to eq("2.2.1")
          expect(error.supported_versions).to eq(">= 3.0")
        end
      end
    end

    context "when the requirement has multiple constraints" do
      let(:requirement) { Dependabot::Python::Requirement.new(">= 2.0, < 3.0") }

      context "when the version is within range" do
        let(:package_manager) { described_class.new("2.2.1", requirement) }

        it "does not raise an error" do
          expect { package_manager.raise_if_unsupported! }.not_to raise_error
        end
      end

      context "when the version is above range" do
        let(:package_manager) { described_class.new("3.1.0", requirement) }

        it "raises ToolVersionNotSupported" do
          expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
        end
      end

      context "when the version is below range" do
        let(:package_manager) { described_class.new("1.8.3", requirement) }

        it "raises ToolVersionNotSupported" do
          expect { package_manager.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
        end
      end
    end
  end
end
