# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub/package_manager"
require "dependabot/nub/helpers"

RSpec.describe Dependabot::Nub::PackageManagerHelper do
  subject(:helper) do
    described_class.new(
      config,
      lockfiles,
      {},
      []
    )
  end

  let(:config) { Dependabot::Package::NpmPackageManagerConfig.from_package_json(package_json) }
  let(:package_json) { {} }
  let(:lockfiles) { {} }

  describe "#detect_version" do
    subject(:detected_version) { helper.detect_version("nub") }

    context "with a packageManager version" do
      let(:package_json) do
        {
          "packageManager" => "nub@1.2.3",
          "engines" => { "nub" => ">=0.0.1" }
        }
      end

      it "prefers packageManager over engines" do
        expect(detected_version).to eq("1.2.3")
      end
    end

    context "with an engine constraint" do
      let(:package_json) { { "engines" => { "nub" => ">=0.0.1" } } }

      it "selects the highest supported version" do
        expect(detected_version).to eq("0.0.1")
      end
    end

    context "with a null engine constraint" do
      let(:package_json) { { "engines" => { "nub" => nil } } }

      it "treats the constraint as missing" do
        expect(detected_version).to be_nil
      end
    end

    context "with only a lockfile" do
      let(:nub_lock) { instance_double(Dependabot::DependencyFile) }
      let(:lockfiles) { { nub: nub_lock } }

      it "uses the typed Nub lockfile fallback" do
        allow(Dependabot::Nub::Helpers).to receive(:nub_version_numeric).with(nub_lock).and_return(1)

        expect(detected_version).to eq("1")
        expect(Dependabot::Nub::Helpers).to have_received(:nub_version_numeric).with(nub_lock)
      end
    end
  end

  describe "#find_engine_constraints_as_requirement" do
    let(:package_json) { { "engines" => { "node" => ">=20" } } }

    it "builds a requirement from the typed engine constraint" do
      expect(helper.find_engine_constraints_as_requirement("node").to_s).to eq(">= 20")
    end
  end
end
