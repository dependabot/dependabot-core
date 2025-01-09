# typed: false
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/experiments"
require "dependabot/ecosystem"
require "dependabot/notices"
require "debug"

# A stub package manager for testing purposes.
class StubVersionManager < Dependabot::Ecosystem::VersionManager
  def initialize(name:, detected_version:, raw_version:, deprecated_versions: [], supported_versions: [],
                 support_later_versions: false)
    @support_later_versions = support_later_versions
    super(
      name: name,
      detected_version: Dependabot::Version.new(detected_version),
      version: raw_version.nil? ? nil : Dependabot::Version.new(raw_version),
      deprecated_versions: deprecated_versions,
      supported_versions: supported_versions
    )
  end

  attr_reader :support_later_versions

  sig { override.returns(T::Boolean) }
  def unsupported?
    return false unless version

    version < supported_versions.first
  end

  sig { override.returns(T::Boolean) }
  def support_later_versions?
    support_later_versions
  end
end

RSpec.describe Dependabot::Notice do
  let(:detected_version) { Dependabot::Version.new("1") }
  let(:raw_version) { Dependabot::Version.new("1.0.1") }
  let(:deprecated_versions) { [Dependabot::Version.new("1")] }
  let(:supported_versions) { [Dependabot::Version.new("2"), Dependabot::Version.new("3")] }
  let(:support_later_versions) { false }
  let(:version_manager_type) { :package_manager }

  let(:version_manager) do
    StubVersionManager.new(
      name: "bundler",
      detected_version: detected_version,
      raw_version: raw_version,
      deprecated_versions: deprecated_versions,
      supported_versions: supported_versions,
      support_later_versions: support_later_versions
    )
  end

  describe ".generate_supported_versions_description" do
    subject(:generate_supported_versions_description) do
      described_class.generate_supported_versions_description(supported_versions, support_later_versions)
    end

    context "when supported_versions has one version" do
      let(:supported_versions) { [Dependabot::Version.new("2")] }

      context "with support_later_versions as false" do
        let(:support_later_versions) { false }

        it "returns the correct description" do
          expect(generate_supported_versions_description).to eq("Please upgrade to version `v2`.")
        end
      end

      context "with support_later_versions as true" do
        let(:support_later_versions) { true }

        it "returns the correct description with later versions supported" do
          expect(generate_supported_versions_description).to eq("Please upgrade to version `v2`, or later.")
        end
      end
    end

    context "when supported_versions has multiple versions" do
      let(:supported_versions) { [Dependabot::Version.new("2"), Dependabot::Version.new("3")] }

      context "with support_later_versions as false" do
        let(:support_later_versions) { false }

        it "returns the correct description without later versions supported" do
          expect(generate_supported_versions_description)
            .to eq("Please upgrade to one of the following versions: `v2`, or `v3`.")
        end
      end

      context "with support_later_versions as true" do
        let(:support_later_versions) { true }

        it "returns the correct description with later versions supported" do
          expect(generate_supported_versions_description)
            .to eq("Please upgrade to one of the following versions: `v2`, `v3`, or later.")
        end
      end
    end

    context "when supported_versions is empty" do
      let(:supported_versions) { [] }

      it "returns a generic upgrade message" do
        expect(generate_supported_versions_description).to eq("Please upgrade your package manager version")
      end
    end
  end

  describe ".generate_deprecation_notice" do
    subject(:deprecation_notice) do
      described_class.generate_deprecation_notice(version_manager, version_manager_type)
    end

    context "when detected_version is deprecated" do
      let(:detected_version) { Dependabot::Version.new("1") }
      let(:deprecated_versions) { [Dependabot::Version.new("1")] }

      context "with raw_version not deprecated" do
        let(:raw_version) { Dependabot::Version.new("2.0.1") }

        it "returns a deprecation notice using detected_version" do
          expect(deprecation_notice.to_hash)
            .to eq({
              mode: "WARN",
              type: "bundler_deprecated_warn",
              package_manager_name: "bundler",
              title: "Package manager deprecation notice",
              description: "Dependabot will stop supporting `bundler v1`!" \
                           "\n\nPlease upgrade to one of the following versions: `v2`, or `v3`.\n",
              show_in_pr: true,
              show_alert: true
            })
        end
      end

      context "with raw_version nil" do
        let(:raw_version) { nil }

        it "returns a deprecation notice using detected_version" do
          expect(deprecation_notice.to_hash)
            .to eq({
              mode: "WARN",
              type: "bundler_deprecated_warn",
              package_manager_name: "bundler",
              title: "Package manager deprecation notice",
              description: "Dependabot will stop supporting `bundler v1`!" \
                           "\n\nPlease upgrade to one of the following versions: `v2`, or `v3`.\n",
              show_in_pr: true,
              show_alert: true
            })
        end
      end
    end

    context "when detected_version is not deprecated" do
      let(:detected_version) { Dependabot::Version.new("2") }
      let(:deprecated_versions) { [Dependabot::Version.new("1")] }

      context "with raw_version nil" do
        let(:raw_version) { nil }

        it "does not return a notice" do
          expect(deprecation_notice).to be_nil
        end
      end

      context "with raw_version different from detected_version" do
        let(:raw_version) { Dependabot::Version.new("1.0.1") }

        it "does not return a notice" do
          expect(deprecation_notice).to be_nil
        end
      end
    end
  end
end
