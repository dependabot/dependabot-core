# typed: false
# frozen_string_literal: true

require "dependabot/docker/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Docker::DockerPackageManager do
  let(:package_manager) do
    described_class.new
  end

  describe "#initialize" do
    context "when docker package manager is initialised" do
      it "sets the name and version correctly" do
        expect(package_manager.name).to eq(Dependabot::Docker::DockerPackageManager::NAME)
        expect(package_manager.version.to_s).to eq("1.0.0")
      end
    end

    describe "#deprecated?" do
      it "returns always false" do
        expect(package_manager.deprecated?).to be false
      end
    end

    describe "#unsupported?" do
      it "returns always false" do
        expect(package_manager.unsupported?).to be false
      end
    end
  end
end
