# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/security_advisory"
require "dependabot/config/ignore_condition"
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

    context "when the latest registry release is not representable in a module specification" do
      let(:available_versions) { ["2.0.0.0.1", "1.5.0", "1.0.0"] }
      let(:dependency_version) { "1.0.0" }
      let(:dependency_requirement) { "= 1.0.0" }

      it "preserves registry discovery and selects the highest representable update candidate" do
        expect(checker.latest_version.to_s).to eq("2.0.0.0.1")
        expect(checker.latest_resolvable_version.to_s).to eq("1.5.0")

        updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first
        expect(updated_dependency).to have_attributes(version: "1.5.0", previous_version: "1.0.0")
        expect(updated_dependency.requirements.first.requirement).to eq("= 1.5.0")
      end
    end

    context "when no registry release is representable in a module specification" do
      let(:available_versions) { ["2.0.0.0.1"] }
      let(:dependency_version) { "1.0.0" }
      let(:dependency_requirement) { "= 1.0.0" }

      it "does not emit an invalid native declaration update" do
        expect(checker.latest_version.to_s).to eq("2.0.0.0.1")
        expect(checker.latest_resolvable_version).to be_nil
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
      end
    end

    context "when representable releases are equal under registry SemVer but not native comparison" do
      let(:dependency_version) { "1.1" }
      let(:dependency_requirement) { "= 1.1" }

      it "selects the longer native version regardless of registry order" do
        [%w(1.2 1.2.0), %w(1.2.0 1.2)].each do |versions|
          body = feed_xml(entries: versions.map { |version| entry_xml(version: version) })
          stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
          fresh_checker = described_class.new(
            dependency: dependency,
            dependency_files: [],
            credentials: [],
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          )

          expect(fresh_checker.latest_resolvable_version.to_s).to eq("1.2.0")
        end
      end
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

    context "when the first safe release is a prerelease" do
      let(:dependency_version) { "1.0.0" }
      let(:dependency_requirement) { "= 1.0.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "Pester",
            package_manager: "powershell",
            vulnerable_versions: ["<= 1.0.0"]
          )
        ]
      end

      before do
        body = feed_xml(
          entries: [
            entry_xml(version: "1.0.0"),
            entry_xml(version: "1.1.0-beta1", prerelease: "true"),
            entry_xml(version: "1.1.0")
          ]
        )
        stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
      end

      it "selects and writes the first safe native declaration version" do
        expect(checker.lowest_security_fix_version.to_s).to eq("1.1.0")

        updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first
        expect(updated_dependency).to have_attributes(version: "1.1.0", previous_version: "1.0.0")
        expect(updated_dependency.requirements.first.requirement).to eq("= 1.1.0")
      end

      context "when no safe release is representable in a module specification" do
        before do
          body = feed_xml(
            entries: [
              entry_xml(version: "1.0.0"),
              entry_xml(version: "1.1.0-beta1", prerelease: "true")
            ]
          )
          stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)
        end

        it "does not emit an invalid native declaration update" do
          expect(checker.lowest_security_fix_version).to be_nil
          expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
        end
      end
    end
  end

  describe "#updated_requirements" do
    it "bumps the RequiredVersion pin to the latest version" do
      updated = checker.updated_requirements.first
      expect(updated.requirement).to eq("= 5.4.0")
    end

    it "does not fetch manifest GUID metadata for an unqualified update" do
      expect(checker.updated_requirements.first.requirement).to eq("= 5.4.0")
      expect(a_request(:get, latest_manifest_url)).not_to have_been_made
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

      let(:target_manifest_body) do
        "@{ GUID = '22222222-2222-2222-2222-222222222222' }"
      end

      before do
        stub_request(:get, latest_manifest_url).to_return(
          status: 200,
          body: target_manifest_body
        )
      end

      it "includes the selected release GUID in the updated requirement metadata" do
        expect(checker.updated_requirements.first.metadata).to include(
          updated_guid: "22222222-2222-2222-2222-222222222222"
        )
      end

      context "when the selected release manifest returns an HTTP error" do
        before do
          stub_request(:get, latest_manifest_url).to_return(status: 500, body: "")
        end

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::RegistryError) do |error|
              expect(error.status).to eq(500)
            end
        end
      end

      context "when the selected release manifest is malformed" do
        let(:target_manifest_body) { "@{ GUID = '22222222-2222-2222-2222-222222222222 }" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end
      end

      context "when the selected release manifest has no GUID" do
        let(:target_manifest_body) { "@{ ModuleVersion = '5.4.0' }" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end
      end

      context "when the selected release manifest has an invalid GUID" do
        let(:target_manifest_body) { "@{ GUID = 'not-a-guid' }" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Pester.*5\.4\.0.*valid GUID/i)
        end
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

    context "when a GUID-qualified RequiredVersion is already at the selected version" do
      let(:dependency_version) { "5.4.0" }
      let(:dependency_requirement) { "= 5.4.0" }
      let(:requirements) do
        [{
          requirement: dependency_requirement,
          groups: [],
          source: source,
          file: "module.psd1",
          metadata: {
            version_key: "RequiredVersion",
            guid: "11111111-1111-1111-1111-111111111111"
          }
        }]
      end

      it "does not require a manifest GUID lookup" do
        expect(checker.updated_requirements.first.requirement).to eq("= 5.4.0")
        expect(a_request(:get, latest_manifest_url)).not_to have_been_made
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

      let(:mar_manifest_metadata) do
        JSON.dump(
          "ModuleVersion" => "5.5.2",
          "GUID" => "17a2feff-488b-47f9-8729-e2cec094624c"
        )
      end
      let(:mar_manifest_status) { 200 }
      let(:mar_manifest_body) do
        JSON.dump(
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
            "annotations" => { "metadata" => mar_manifest_metadata }
          }]
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
          status: mar_manifest_status,
          body: mar_manifest_body
        )
      end

      it "updates the version and GUID from the same MAR source" do
        updated = checker.updated_requirements.first

        expect(updated.requirement).to eq("= 5.5.2")
        expect(updated.metadata).to include(updated_guid: "17a2feff-488b-47f9-8729-e2cec094624c")
        expect(updated.source).to eq(
          type: "registry",
          url: "https://mcr.microsoft.com"
        )
      end

      context "when the selected MAR manifest returns a server error" do
        let(:mar_manifest_status) { 503 }
        let(:mar_manifest_body) { "" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::RegistryError) do |error|
              expect(error.status).to eq(503)
            end
        end
      end

      context "when the selected MAR manifest is not found" do
        let(:mar_manifest_status) { 404 }
        let(:mar_manifest_body) { "" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::RegistryError) do |error|
              expect(error.status).to eq(404)
            end
        end
      end

      context "when the selected MAR manifest metadata is malformed" do
        let(:secret) { "MAR_METADATA_SECRET" }
        let(:mar_manifest_metadata) { %({"access_token":#{secret}}) }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to match(/Az\.Accounts.*5\.5\.2.*metadata/i)
              expect(error.full_message).not_to include(secret, "access_token")
              expect(error.cause).to be_nil
            end
        end
      end

      context "when the selected MAR manifest has an invalid document shape" do
        let(:mar_manifest_body) { "null" }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Az\.Accounts.*5\.5\.2.*manifest/i)
        end
      end

      context "when the selected MAR manifest contains malformed JSON" do
        let(:secret) { "MAR_MANIFEST_SECRET" }
        let(:mar_manifest_body) { %({"access_token":#{secret}}) }

        it "does not emit a version update with the stale GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to match(/Az\.Accounts.*5\.5\.2.*manifest/i)
              expect(error.full_message).not_to include(secret, "access_token")
              expect(error.cause).to be_nil
            end
        end
      end

      context "when the selected MAR manifest is not a JSON object" do
        let(:mar_manifest_body) do
          JSON.dump(
            [
              ["schemaVersion", 2],
              ["layers", [{
                "annotations" => { "metadata" => mar_manifest_metadata }
              }]]
            ]
          )
        end

        it "does not accept an array coerced into a manifest" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /Az\.Accounts.*5\.5\.2.*manifest/i)
        end
      end

      context "when the selected MAR manifest contains an invalid UTF-8 GUID" do
        let(:mar_manifest_body) do
          %({
            "layers":[{
              "annotations":{
                "metadata":"{\\"GUID\\":\\"17a2feff-488b-47f9-8729-e2cec094624c\xFF\\"}"
              }
            }]
          }).b.force_encoding(Encoding::UTF_8)
        end

        it "does not emit an update with an unvalidated GUID" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to match(/Az\.Accounts.*5\.5\.2.*valid GUID/i)
              expect(error.cause).to be_nil
            end
        end
      end

      context "when the selected MAR manifest has a certificate failure" do
        before do
          stub_request(
            :get,
            "https://mcr.microsoft.com/v2/psresource/az.accounts/manifests/5.5.2"
          ).to_raise(DockerRegistry2::RegistrySSLException)
        end

        it "raises a typed certificate error instead of emitting an update" do
          expect { checker.updated_dependencies(requirements_to_unlock: :own) }
            .to raise_error(Dependabot::PrivateSourceCertificateFailure) do |error|
              expect(error.source).to eq("https://mcr.microsoft.com")
            end
        end
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

      it "can update by unlocking its own requirement" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end

      it "returns the padded version and requirement through the public update path" do
        expect(checker.updated_requirements.first.requirement).to eq("= 0.12.0")

        updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first
        expect(updated_dependency).to have_attributes(
          version: "0.12.0",
          previous_version: "0.12"
        )
        expect(updated_dependency.requirements.first.requirement).to eq("= 0.12.0")
      end
    end

    context "when registry ordering treats native versions as equal" do
      it "uses the native-sorted candidate for freshness regardless of release order" do
        [%w(1.2 1.2.0), %w(1.2.0 1.2)].each do |versions|
          body = feed_xml(entries: versions.map { |version| entry_xml(version: version) })
          stub_request(:get, find_packages_by_id_url).to_return(status: 200, body: body)

          current_checker = described_class.new(
            dependency: Dependabot::Dependency.new(
              name: "Pester",
              version: "1.2.0",
              requirements: [requirements.first.merge(requirement: "= 1.2.0")],
              package_manager: "powershell"
            ),
            dependency_files: [],
            credentials: [],
            ignored_versions: [],
            security_advisories: []
          )
          update_checker = described_class.new(
            dependency: Dependabot::Dependency.new(
              name: "Pester",
              version: "1.2",
              requirements: [requirements.first.merge(requirement: "= 1.2")],
              package_manager: "powershell"
            ),
            dependency_files: [],
            credentials: [],
            ignored_versions: [],
            security_advisories: []
          )

          expect(current_checker.up_to_date?).to be(true)
          expect(current_checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
          expect(update_checker.up_to_date?).to be(false)
          expect(update_checker.updated_dependencies(requirements_to_unlock: :own).first.version).to eq("1.2.0")
        end
      end
    end

    context "when patch updates are ignored" do
      let(:available_versions) { %w(1.2 1.2.0) }
      let(:dependency_version) { "1.2" }
      let(:dependency_requirement) { "= 1.2" }
      let(:ignored_versions) do
        Dependabot::Config::IgnoreCondition.new(
          dependency_name: "Pester",
          update_types: [Dependabot::Config::IgnoreCondition::PATCH_VERSION_TYPE]
        ).ignored_versions(dependency, false)
      end

      it "does not emit a component-count-only patch update" do
        expect(ignored_versions).to contain_exactly("> 1.2, < 1.3", "= 1.2.0", "= 1.2.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
      end
    end

    context "when an exact pin differs from the latest version only by leading zeroes" do
      let(:available_versions) { ["1.2"] }
      let(:dependency_version) { "01.02" }
      let(:dependency_requirement) { "= 01.02" }

      it "is up to date" do
        expect(checker.up_to_date?).to be(true)
      end

      it "does not produce an update for the normalized equivalent" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
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

    describe "requirement-only update versions" do
      context "when a ModuleVersion minimum is updated" do
        let(:available_versions) { ["1.3.0"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { ">= 1.2.3" }
        let(:requirements) do
          [{
            requirement: dependency_requirement,
            groups: [],
            source: source,
            file: "module.psd1",
            metadata: { version_key: "ModuleVersion" }
          }]
        end

        it "uses the prior minimum as the previous version" do
          updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first

          expect(updated_dependency).to have_attributes(version: "1.3.0", previous_version: "1.2.3")
        end
      end

      context "when a MaximumVersion cap is updated" do
        let(:available_versions) { ["1.2.4"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { "<= 1.2.3" }
        let(:requirements) do
          [{
            requirement: dependency_requirement,
            groups: [],
            source: source,
            file: "module.psd1",
            metadata: { version_key: "MaximumVersion" }
          }]
        end

        it "uses the prior maximum as the previous version" do
          updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first

          expect(updated_dependency).to have_attributes(version: "1.2.4", previous_version: "1.2.3")
        end
      end

      context "when a bounded range maximum is updated" do
        let(:available_versions) { ["2.0.0"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { ">= 1.0.0, <= 1.2.3" }
        let(:requirements) do
          [{
            requirement: dependency_requirement,
            groups: [],
            source: source,
            file: "module.psd1",
            metadata: { version_key: "ModuleVersion+MaximumVersion" }
          }]
        end

        it "uses the prior maximum as the previous version" do
          updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first

          expect(updated_dependency).to have_attributes(version: "2.0.0", previous_version: "1.2.3")
        end
      end

      context "when the declaration has no version" do
        let(:available_versions) { ["1.2.3"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { nil }
        let(:requirements) do
          [{ requirement: nil, groups: [], source: source, file: "module.psd1", metadata: {} }]
        end

        it "does not invent a previous version" do
          expect(checker.latest_resolvable_previous_version("1.2.3")).to be_nil
        end
      end

      context "when an unchanged maximum precedes a changed minimum" do
        let(:available_versions) { ["1.5.0"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { nil }
        let(:requirements) do
          [
            {
              requirement: "<= 2.0.0",
              groups: [],
              source: source,
              file: "module.psd1",
              metadata: { version_key: "MaximumVersion" }
            },
            {
              requirement: ">= 1.0.0",
              groups: [],
              source: source,
              file: "module.psd1",
              metadata: { version_key: "ModuleVersion" }
            }
          ]
        end

        it "uses the bound from the requirement that changed" do
          updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first

          expect(updated_dependency).to have_attributes(version: "1.5.0", previous_version: "1.0.0")
        end
      end

      context "when different prior bounds both change" do
        let(:available_versions) { ["1.5.0"] }
        let(:dependency_version) { nil }
        let(:dependency_requirement) { nil }
        let(:requirements) do
          [
            {
              requirement: ">= 1.0.0",
              groups: [],
              source: source,
              file: "module.psd1",
              metadata: { version_key: "ModuleVersion" }
            },
            {
              requirement: "<= 1.2.0",
              groups: [],
              source: source,
              file: "module.psd1",
              metadata: { version_key: "MaximumVersion" }
            }
          ]
        end

        it "leaves the previous version unset rather than misclassifying the update" do
          updated_dependency = checker.updated_dependencies(requirements_to_unlock: :own).first

          expect(updated_dependency).to have_attributes(version: "1.5.0", previous_version: nil)
        end
      end
    end
  end
end
