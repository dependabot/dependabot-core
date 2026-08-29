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
  let(:latest_manifest_url) do
    "https://www.powershellgallery.com/packages/Pester/5.4.0/Content/Pester.psd1"
  end
  let(:mar_tags_url) { "https://mcr.microsoft.com/v2/psresource/#{dependency.name.downcase}/tags/list" }
  let(:available_versions) { %w(5.4.0 5.3.3) }
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
    stub_request(:get, mar_tags_url).to_return(status: 404, body: "")
    body = feed_xml(
      entries: available_versions.map { |version| entry_xml(version:) }
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

    context "when a GUID-qualified RequiredVersion has changed" do
      let(:requirements) do
        [{
          requirement: "= 5.3.3",
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: {
            version_key: "RequiredVersion",
            guid: "11111111-1111-1111-1111-111111111111"
          }
        }]
      end

      before do
        stub_request(:get, latest_manifest_url).to_return(
          status: 200,
          body: "@{ GUID = '22222222-2222-2222-2222-222222222222' }"
        )
      end

      it "includes the selected release GUID in the updated requirement metadata" do
        expect(checker.updated_requirements.first.metadata).to include(
          updated_guid: "22222222-2222-2222-2222-222222222222"
        )
      end
    end

    context "when a GUID-qualified RequiredVersion has the same selected release GUID" do
      let(:requirements) do
        [{
          requirement: "= 5.3.3",
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: {
            version_key: "RequiredVersion",
            guid: "11111111-1111-1111-1111-111111111111"
          }
        }]
      end

      before do
        stub_request(:get, latest_manifest_url).to_return(
          status: 200,
          body: "@{ GUID = '11111111-1111-1111-1111-111111111111' }"
        )
      end

      it "does not add a GUID update to the requirement metadata" do
        expect(checker.updated_requirements.first.metadata).not_to have_key(:updated_guid)
      end
    end

    context "when a GUID-qualified dependency is available from Microsoft Artifact Registry" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Az.Accounts",
          version: "4.0.0",
          requirements: [{
            requirement: "= 4.0.0",
            groups: [],
            source: source,
            file: "module.psd1",
            metadata: {
              version_key: "RequiredVersion",
              guid: "11111111-1111-1111-1111-111111111111"
            }
          }],
          package_manager: "powershell"
        )
      end

      before do
        stub_request(:get, mar_tags_url).to_return(
          status: 200,
          body: JSON.dump("name" => "psresource/az.accounts", "tags" => ["4.0.0", "5.5.2"])
        )
        stub_request(
          :get,
          "https://mcr.microsoft.com/v2/psresource/az.accounts/manifests/5.5.2"
        ).to_return(
          status: 200,
          body: JSON.dump(
            "schemaVersion" => 2,
            "mediaType" => "application/vnd.oci.image.manifest.v1+json",
            "config" => {
              "mediaType" => "application/vnd.oci.image.config.v1+json",
              "digest" => "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "size" => 0
            },
            "layers" => [{
              "mediaType" => "application/vnd.oci.image.layer.v1.tar+gzip",
              "digest" => "sha256:4465339b2c52cb19d0cb6ee16467076cd7f32633e9195df675373eb81e0e8cca",
              "size" => 10_201_874,
              "annotations" => {
                "metadata" => JSON.dump(
                  "ModuleVersion" => "5.5.2",
                  "GUID" => "17a2feff-488b-47f9-8729-e2cec094624c"
                )
              }
            }]
          )
        )
      end

      it "updates the version and GUID from the same MAR source" do
        updated = checker.updated_requirements.first

        expect(updated.requirement).to eq("= 5.5.2")
        expect(updated.metadata).to include(updated_guid: "17a2feff-488b-47f9-8729-e2cec094624c")
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

    context "when an exact pin differs from the latest version only by zero padding" do
      let(:available_versions) { ["0.12.0"] }
      let(:dependency_version) { "0.12" }
      let(:dependency_requirement) { "= 0.12" }

      it "is not up to date" do
        expect(checker.up_to_date?).to be(false)
      end
    end

    context "when the dependency has no version and a bounded range requirement" do
      let(:dependency_version) { nil }
      let(:dependency_requirement) { ">= 1.0.0, <= 6.0.0" }
      let(:requirements) do
        [{
          requirement: dependency_requirement,
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: { version_key: "ModuleVersion+MaximumVersion" }
        }]
      end

      it "is up to date, since the latest version satisfies the declared range" do
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when the dependency has no version and the latest version exceeds the declared range" do
      let(:dependency_version) { nil }
      let(:dependency_requirement) { ">= 1.0.0, <= 5.3.3" }
      let(:requirements) do
        [{
          requirement: dependency_requirement,
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: { version_key: "ModuleVersion+MaximumVersion" }
        }]
      end

      it "is not up to date" do
        expect(checker.up_to_date?).to be(false)
      end
    end

    context "when the dependency has no version and declares a ModuleVersion minimum" do
      let(:dependency_version) { nil }
      let(:dependency_requirement) { ">= 5.0.0" }
      let(:requirements) do
        [{
          requirement: dependency_requirement,
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: { version_key: "ModuleVersion" }
        }]
      end

      it "is not up to date, because the floor tracks the latest version" do
        expect(checker.up_to_date?).to be(false)
      end
    end
  end
end
