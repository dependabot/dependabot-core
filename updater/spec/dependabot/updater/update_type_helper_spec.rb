# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/version"
require "dependabot/updater/update_type_helper"
require "support/dummy_package_manager/version"

RSpec.describe Dependabot::Updater::UpdateTypeHelper do
  # Create a test class that includes the module
  let(:helper_class) do
    Class.new do
      include Dependabot::Updater::UpdateTypeHelper
    end
  end

  let(:helper) { helper_class.new }

  let(:version_with_semver_parts) do
    Class.new(Dependabot::Version) do
      def semver_parts
        [1, 2, 3]
      end
    end
  end

  let(:version_without_semver_parts) do
    Class.new(Dependabot::Version) do
      def semver_parts
        nil
      end

      def to_s
        "invalid"
      end
    end
  end

  describe "#semver_parts" do
    context "when version responds to semver_parts" do
      it "returns SemverParts from the version's semver_parts method" do
        version = version_with_semver_parts.new("1.2.3")

        result = helper.semver_parts(version)

        expect(result).to be_a(Dependabot::Updater::UpdateTypeHelper::SemverParts)
        expect(result.major).to eq(1)
        expect(result.minor).to eq(2)
        expect(result.patch).to eq(3)
      end

      it "returns nil when semver_parts returns nil" do
        version = version_without_semver_parts.new("1.0.0")

        result = helper.semver_parts(version)

        expect(result).to be_nil
      end
    end

    context "when version is parsed from string" do
      context "with standard semver format" do
        it "returns SemverParts for '1.2.3'" do
          version = instance_double(Gem::Version, to_s: "1.2.3")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(3)
        end

        it "returns SemverParts with zero defaults for partial versions" do
          version = instance_double(Gem::Version, to_s: "1")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end

        it "handles two-part versions" do
          version = instance_double(Gem::Version, to_s: "1.2")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(0)
        end
      end

      context "with 'v' prefix" do
        it "strips 'v' prefix and extracts numeric parts for 'v1.0.0'" do
          version = instance_double(Gem::Version, to_s: "v1.0.0")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end

        it "strips 'v' prefix and extracts numeric parts for 'v1.1.1'" do
          version = instance_double(Gem::Version, to_s: "v1.1.1")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(1)
          expect(result.patch).to eq(1)
        end

        it "handles v2.3.4 correctly" do
          version = instance_double(Gem::Version, to_s: "v2.3.4")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(2)
          expect(result.minor).to eq(3)
          expect(result.patch).to eq(4)
        end
      end

      context "with non-numeric segments" do
        it "returns nil when all segments are non-numeric" do
          version = instance_double(Gem::Version, to_s: "alpha.beta.gamma")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end

      context "with empty string" do
        it "returns nil for empty string" do
          version = instance_double(Gem::Version, to_s: "")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end
    end
  end

  describe "#classify_semver_update" do
    before do
      allow(Dependabot).to receive(:logger).and_return(instance_double(Logger, info: nil))
    end

    it "returns 'major' for major version bump" do
      prev_version = DummyPackageManager::Version.new("1.0.0")
      curr_version = DummyPackageManager::Version.new("2.0.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end

    it "returns 'minor' for minor version bump" do
      prev_version = DummyPackageManager::Version.new("1.0.0")
      curr_version = DummyPackageManager::Version.new("1.1.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("minor")
    end

    it "returns 'patch' for patch version bump" do
      prev_version = DummyPackageManager::Version.new("1.0.0")
      curr_version = DummyPackageManager::Version.new("1.0.1")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("patch")
    end

    it "handles versions with 'v' prefix correctly" do
      prev_version = DummyPackageManager::Version.new("v1.0.0")
      curr_version = DummyPackageManager::Version.new("v2.0.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end
  end

  describe "#update_type_for_dependency" do
    before do
      allow(Dependabot).to receive(:logger).and_return(instance_double(Logger, info: nil))
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "my-gem",
        version: current_version,
        previous_version: previous_version,
        requirements: [],
        previous_requirements: [],
        package_manager: package_manager
      )
    end
    let(:package_manager) { "dummy" }

    context "when it is a major update" do
      let(:previous_version) { "1.0.0" }
      let(:current_version) { "2.0.0" }

      it "returns 'major'" do
        expect(helper.update_type_for_dependency(dependency)).to eq("major")
      end
    end

    context "when it is a minor update" do
      let(:previous_version) { "1.0.0" }
      let(:current_version) { "1.1.0" }

      it "returns 'minor'" do
        expect(helper.update_type_for_dependency(dependency)).to eq("minor")
      end
    end

    context "when it is a patch update" do
      let(:previous_version) { "1.0.0" }
      let(:current_version) { "1.0.1" }

      it "returns 'patch'" do
        expect(helper.update_type_for_dependency(dependency)).to eq("patch")
      end
    end

    context "when previous_version is nil" do
      let(:previous_version) { nil }
      let(:current_version) { "1.0.0" }

      it "returns nil" do
        expect(helper.update_type_for_dependency(dependency)).to be_nil
      end
    end

    context "when version is nil" do
      let(:previous_version) { "1.0.0" }
      let(:current_version) { nil }

      it "returns nil" do
        expect(helper.update_type_for_dependency(dependency)).to be_nil
      end
    end

    context "when versions are the same" do
      let(:previous_version) { "1.0.0" }
      let(:current_version) { "1.0.0" }

      it "returns nil" do
        expect(helper.update_type_for_dependency(dependency)).to be_nil
      end
    end

    context "with PowerShell versions" do
      let(:package_manager) { "powershell" }

      it "classifies major, minor, patch, and revision-only updates" do
        expected_types = {
          ["1.2.3", "2.0.0"] => "major",
          ["1.2.3", "1.3.0"] => "minor",
          ["1.2.3", "1.2.4"] => "patch",
          ["1.2.3.4", "1.2.3.5"] => "patch",
          ["1.2", "1.2.0"] => "patch"
        }

        expected_types.each do |(previous, current), expected_type|
          updated_dependency = Dependabot::Dependency.new(
            name: "Pester",
            version: current,
            previous_version: previous,
            requirements: [],
            previous_requirements: [],
            package_manager: package_manager
          )

          expect(helper.update_type_for_dependency(updated_dependency)).to eq(expected_type)
        end
      end

      it "does not classify removal of a native version component as an update" do
        updated_dependency = Dependabot::Dependency.new(
          name: "Pester",
          version: "1.2",
          previous_version: "1.2.0",
          requirements: [],
          previous_requirements: [],
          package_manager: package_manager
        )

        expect(helper.update_type_for_dependency(updated_dependency)).to be_nil
      end

      it "classifies each requirement-only declaration style from its previous bound" do
        expected_types = {
          "ModuleVersion" => ["1.2.3", "1.3.0", "minor"],
          "MaximumVersion" => ["1.2.3", "1.2.4", "patch"],
          "ModuleVersion+MaximumVersion" => ["1.2.3", "2.0.0", "major"]
        }

        expected_types.each do |version_key, (previous, current, expected_type)|
          updated_dependency = Dependabot::Dependency.new(
            name: "Pester",
            version: current,
            previous_version: previous,
            requirements: [{
              requirement: "= #{current}",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: version_key }
            }],
            previous_requirements: [{
              requirement: "= #{previous}",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: version_key }
            }],
            package_manager: package_manager
          )

          expect(helper.update_type_for_dependency(updated_dependency)).to eq(expected_type)
        end
      end

      it "leaves same-core prerelease-only changes unclassified" do
        updated_dependency = Dependabot::Dependency.new(
          name: "Pester",
          version: "1.2.3-beta2",
          previous_version: "1.2.3-beta1",
          requirements: [],
          previous_requirements: [],
          package_manager: package_manager
        )

        expect(helper.update_type_for_dependency(updated_dependency)).to be_nil
      end

      it "leaves an unversioned declaration unclassified" do
        updated_dependency = Dependabot::Dependency.new(
          name: "Pester",
          version: "1.2.3",
          previous_version: nil,
          requirements: [],
          previous_requirements: [],
          package_manager: package_manager
        )

        expect(helper.update_type_for_dependency(updated_dependency)).to be_nil
      end

      it "leaves an ambiguous requirement-only update unclassified" do
        updated_dependency = Dependabot::Dependency.new(
          name: "Pester",
          version: "1.5.0",
          previous_version: nil,
          requirements: [
            {
              requirement: ">= 1.5.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "ModuleVersion" }
            },
            {
              requirement: "<= 1.5.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "MaximumVersion" }
            }
          ],
          previous_requirements: [
            {
              requirement: ">= 1.0.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "ModuleVersion" }
            },
            {
              requirement: "<= 1.2.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "MaximumVersion" }
            }
          ],
          package_manager: package_manager
        )

        expect(helper.update_type_for_dependency(updated_dependency)).to be_nil
      end

      it "classifies a mixed requirement-only update from its changed bound" do
        updated_dependency = Dependabot::Dependency.new(
          name: "Pester",
          version: "1.5.0",
          previous_version: "1.0.0",
          requirements: [
            {
              requirement: "<= 2.0.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "MaximumVersion" }
            },
            {
              requirement: ">= 1.5.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "ModuleVersion" }
            }
          ],
          previous_requirements: [
            {
              requirement: "<= 2.0.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "MaximumVersion" }
            },
            {
              requirement: ">= 1.0.0",
              groups: [],
              file: "module.psd1",
              source: nil,
              metadata: { version_key: "ModuleVersion" }
            }
          ],
          package_manager: package_manager
        )

        expect(helper.update_type_for_dependency(updated_dependency)).to eq("minor")
      end
    end
  end
end
