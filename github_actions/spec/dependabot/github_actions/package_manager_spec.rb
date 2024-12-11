# typed: false
# frozen_string_literal: true

require "dependabot/github_actions/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::GithubActions::PackageManager do
  let(:package_manager) { described_class.new(use_name, version, requirement) }
  let(:use_name) { "actions/checkout" }
  let(:requirement) { nil }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "v2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::GithubActions::Version.new(version))
      end

      it "sets the use_name correctly" do
        expect(package_manager.use_name).to eq(use_name)
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::GithubActions::PACKAGE_MANAGER)
      end
    end

    context "when version is a Dependabot::GithubActions::Version" do
      let(:version) { "v2" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(version)
      end

      it "sets the use_name correctly" do
        expect(package_manager.use_name).to eq(use_name)
      end
    end
  end

  describe "#version_to_s" do
    let(:version) { "v2" }

    it "returns the full version string with use_name" do
      expect(package_manager.version_to_s).to eq("#{use_name}@#{version}")
    end
  end

  describe "#version_to_raw_s" do
    let(:version) { "v2" }

    it "returns the raw version string with use_name" do
      expect(package_manager.version_to_raw_s).to eq("#{use_name}@#{version}")
    end
  end

  describe "#deprecated?" do
    let(:version) { "v2" }

    it "returns false as GitHub Actions does not have deprecated versions yet" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    let(:version) { "v2" }

    it "returns false as GitHub Actions does not have unsupported versions yet" do
      expect(package_manager.unsupported?).to be false
    end
  end
end
