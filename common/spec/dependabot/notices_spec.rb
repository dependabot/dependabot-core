# typed: false
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/experiments"
require "dependabot/ecosystem"
require "dependabot/notices"

# A stub package manager for testing purposes.
class StubPackageManager < Dependabot::Ecosystem::VersionManager
  def initialize(name:, version:, deprecated_versions: [], unsupported_versions: [], supported_versions: [],
                 support_later_versions: false)
    @name = name
    @version = version
    @deprecated_versions = deprecated_versions
    @unsupported_versions = unsupported_versions
    @supported_versions = supported_versions
    @support_later_versions = support_later_versions
  end

  attr_reader :name
  attr_reader :version
  attr_reader :deprecated_versions
  attr_reader :unsupported_versions
  attr_reader :supported_versions
  attr_reader :support_later_versions

  sig { override.returns(T::Boolean) }
  def deprecated?
    # If the version is unsupported, the unsupported error is getting raised separately.
    return false if unsupported?

    deprecated_versions.include?(version)
  end

  sig { override.returns(T::Boolean) }
  def unsupported?
    # Determine if the Bundler version is unsupported.
    version < supported_versions.first
  end
end

RSpec.describe Dependabot::Notice do
  describe ".generate_supported_versions_description" do
    subject(:generate_supported_versions_description) do
      described_class.generate_supported_versions_description(supported_versions, support_later_versions)
    end

    context "when supported_versions has one version" do
      let(:supported_versions) { [Dependabot::Version.new("2")] }
      let(:support_later_versions) { false }

      it "returns the correct description" do
        expect(generate_supported_versions_description)
          .to eq("Please upgrade to version `v2`.")
      end
    end

    context "when supported_versions has one version and later versions are supported" do
      let(:supported_versions) { [Dependabot::Version.new("2")] }
      let(:support_later_versions) { true }

      it "returns the correct description" do
        expect(generate_supported_versions_description)
          .to eq("Please upgrade to version `v2`, or later.")
      end
    end

    context "when supported_versions has multiple versions" do
      let(:supported_versions) do
        [Dependabot::Version.new("2"), Dependabot::Version.new("3"),
         Dependabot::Version.new("4")]
      end
      let(:support_later_versions) { false }

      it "returns the correct description" do
        expect(generate_supported_versions_description)
          .to eq("Please upgrade to one of the following versions: `v2`, `v3`, or `v4`.")
      end
    end

    context "when supported_versions has multiple versions and later versions are supported" do
      let(:supported_versions) do
        [Dependabot::Version.new("2"), Dependabot::Version.new("3"),
         Dependabot::Version.new("4")]
      end
      let(:support_later_versions) { true }

      it "returns the correct description" do
        expect(generate_supported_versions_description)
          .to eq("Please upgrade to one of the following versions: `v2`, `v3`, `v4`, or later.")
      end
    end

    context "when supported_versions is nil" do
      let(:supported_versions) { nil }
      let(:support_later_versions) { false }

      it "returns empty string" do
        expect(generate_supported_versions_description).to eq("Please upgrade your package manager version")
      end
    end

    context "when supported_versions is empty" do
      let(:supported_versions) { [] }
      let(:support_later_versions) { false }

      it "returns nil" do
        expect(generate_supported_versions_description).to eq("Please upgrade your package manager version")
      end
    end
  end

  describe ".generate_pm_deprecation_notice" do
    subject(:generate_pm_deprecation_notice) do
      described_class.generate_pm_deprecation_notice(package_manager)
    end

    let(:package_manager) do
      StubPackageManager.new(
        name: "bundler",
        version: Dependabot::Version.new("1"),
        deprecated_versions: [Dependabot::Version.new("1")],
        supported_versions: [Dependabot::Version.new("2"), Dependabot::Version.new("3")]
      )
    end

    it "returns the correct deprecation notice" do
      allow(package_manager).to receive(:unsupported?).and_return(false)
      expect(generate_pm_deprecation_notice.to_hash)
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
