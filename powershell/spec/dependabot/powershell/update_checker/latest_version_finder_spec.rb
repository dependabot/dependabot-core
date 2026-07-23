# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/security_advisory"
require "dependabot/package/release_cooldown_options"
require "dependabot/powershell/update_checker/latest_version_finder"

RSpec.describe Dependabot::Powershell::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: false,
      cooldown_options: cooldown_options
    )
  end

  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:cooldown_options) { nil }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Pester",
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        source: { type: "registry", url: "https://www.powershellgallery.com/api/v2" },
        file: "module.psd1"
      }],
      package_manager: "powershell"
    )
  end
  let(:dependency_version) { "5.3.3" }

  let(:find_packages_by_id_url) do
    "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27Pester%27"
  end

  def entry_xml(version:, published: "2023-05-01T12:00:00", prerelease: "false")
    <<~XML
      <entry>
        <content type="application/zip" src="https://www.powershellgallery.com/api/v2/package/Pester/#{version}" />
        <m:properties>
          <d:Version>#{version}</d:Version>
          <d:Published>#{published}</d:Published>
          <d:IsPrerelease>#{prerelease}</d:IsPrerelease>
        </m:properties>
      </entry>
    XML
  end

  def feed_xml(entries:)
    <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
        #{entries.join("\n")}
      </feed>
    XML
  end

  before do
    body = feed_xml(
      entries: [
        entry_xml(version: "5.4.0"),
        entry_xml(version: "5.3.3"),
        entry_xml(version: "5.3.0", published: "1900-01-01T00:00:00"), # unlisted
        entry_xml(version: "5.5.0-beta1", prerelease: "true")
      ]
    )

    stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
  end

  describe "#latest_version" do
    it "returns the highest non-prerelease, non-yanked version" do
      expect(finder.latest_version.to_s).to eq("5.4.0")
    end

    context "when the current version is a prerelease" do
      let(:dependency_version) { "5.5.0-beta1" }

      it "includes prereleases in the candidate set" do
        expect(finder.latest_version.to_s).to eq("5.5.0.pre.beta1")
      end
    end

    context "when the latest version is ignored" do
      let(:ignored_versions) { [">= 5.4.0"] }

      it "returns the highest version that isn't ignored" do
        expect(finder.latest_version.to_s).to eq("5.3.3")
      end
    end

    context "when the highest version is unlisted" do
      before do
        body = feed_xml(
          entries: [
            entry_xml(version: "5.4.0", published: "1900-01-01T00:00:00"),
            entry_xml(version: "5.3.3")
          ]
        )
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "does not rely on gallery IsLatestVersion flags and skips the unlisted release" do
        expect(finder.latest_version.to_s).to eq("5.3.3")
      end
    end
  end

  describe "#latest_version_with_no_unlock" do
    it "returns the latest version compatible with the current requirement" do
      expect(finder.latest_version_with_no_unlock.to_s).to eq("5.4.0")
    end
  end

  describe "#lowest_security_fix_version" do
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "Pester",
          package_manager: "powershell",
          vulnerable_versions: ["<= 5.3.3"]
        )
      ]
    end

    it "returns the lowest version that isn't vulnerable" do
      expect(finder.lowest_security_fix_version.to_s).to eq("5.4.0")
    end
  end
end
