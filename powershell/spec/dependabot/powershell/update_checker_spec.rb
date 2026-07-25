# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/security_advisory"
require "dependabot/powershell/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Powershell::UpdateChecker do
  subject(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end

  let(:find_packages_by_id_url) do
    "https://www.powershellgallery.com/api/v2/FindPackagesById()?id=%27Pester%27"
  end
  let(:dependency_requirement) { "= 5.3.3" }
  let(:requirements) do
    [{
      requirement: dependency_requirement,
      groups: [],
      source: source,
      file: "module.psd1",
      metadata: { version_key: "RequiredVersion" }
    }]
  end
  let(:dependency_version) { "5.3.3" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Pester",
      version: dependency_version,
      requirements: requirements,
      package_manager: "powershell"
    )
  end
  let(:source) { { type: "registry", url: "https://www.powershellgallery.com/api/v2" } }
  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }

  before do
    body = feed_xml(
      entries: [
        entry_xml(version: "5.4.0"),
        entry_xml(version: "5.3.3")
      ]
    )

    stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
  end

  it_behaves_like "an update checker"

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

  describe "#latest_version" do
    it "returns the latest version available on the PowerShell Gallery" do
      expect(checker.latest_version.to_s).to eq("5.4.0")
    end
  end

  describe "#latest_resolvable_version" do
    it "matches the latest version, since PowerShell has no separate resolution step" do
      expect(checker.latest_resolvable_version.to_s).to eq("5.4.0")
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    it "returns a version compatible with the existing requirement" do
      # The declared requirement is an exact pin ("= 5.3.3"), so without
      # unlocking the requirement no other version can be resolved.
      expect(checker.latest_resolvable_version_with_no_unlock.to_s).to eq("5.3.3")
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

    it "returns the lowest non-vulnerable version" do
      expect(checker.lowest_security_fix_version.to_s).to eq("5.4.0")
    end
  end

  describe "#updated_requirements" do
    it "bumps the RequiredVersion pin to the latest version" do
      updated = checker.updated_requirements.first
      expect(updated.requirement).to eq("= 5.4.0")
    end

    it "preserves the version_key metadata for the file updater stage" do
      updated = checker.updated_requirements.first
      expect(updated[:metadata][:version_key]).to eq("RequiredVersion")
    end

    context "when the requirement is a ModuleVersion minimum" do
      let(:requirements) do
        [{
          requirement: ">= 5.0.0",
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: { version_key: "ModuleVersion" }
        }]
      end
      let(:dependency_requirement) { ">= 5.0.0" }

      it "bumps the minimum constraint to track the latest version" do
        updated = checker.updated_requirements.first
        expect(updated.requirement).to eq(">= 5.4.0")
      end
    end

    context "when the requirement is a MaximumVersion cap that excludes the latest version" do
      let(:requirements) do
        [{
          requirement: "<= 5.3.3",
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: { version_key: "MaximumVersion" }
        }]
      end
      let(:dependency_requirement) { "<= 5.3.3" }

      it "raises the cap to the latest version" do
        updated = checker.updated_requirements.first
        expect(updated.requirement).to eq("<= 5.4.0")
      end
    end
  end

  describe "#up_to_date?" do
    context "when the dependency is pinned to the latest version" do
      let(:dependency_version) { "5.4.0" }
      let(:dependency_requirement) { "= 5.4.0" }

      it { expect(checker.up_to_date?).to be(true) }
    end

    context "when a newer version is available" do
      it { expect(checker.up_to_date?).to be(false) }
    end

    context "when the dependency has no version and a bounded range requirement" do
      # No lockfile/installed version is known (`dependency.version` is nil),
      # so `up_to_date?` falls through to `requirements_up_to_date?`. The
      # base implementation would compare the latest version only against
      # the lower bound (">= 1.0.0") and incorrectly report this as not up
      # to date once the latest version (5.4.0) exceeds it - even though
      # 5.4.0 is well within the declared range and RequirementsUpdater
      # correctly leaves the requirement untouched.
      let(:dependency_version) { nil }
      let(:dependency_requirement) { ">= 1.0.0, <= 6.0.0" }

      it "is up to date, since the latest version satisfies the declared range" do
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when the dependency has no version and the latest version exceeds the declared range" do
      let(:dependency_version) { nil }
      let(:dependency_requirement) { ">= 1.0.0, <= 5.3.3" }

      it "is not up to date" do
        expect(checker.up_to_date?).to be(false)
      end
    end
  end
end
