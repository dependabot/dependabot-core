# typed: false
# frozen_string_literal: true

require "spec_helper"
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

  # Simple test version class that supports semver_parts
  let(:version_with_semver_parts) do
    Struct.new(:semver_parts, :to_s)
  end

  describe "#semver_parts" do
    context "when version responds to semver_parts" do
      it "returns SemverParts from the version's semver_parts method" do
        version = version_with_semver_parts.new([1, 2, 3], "1.2.3")

        result = helper.semver_parts(version)

        expect(result).to be_a(Dependabot::Updater::UpdateTypeHelper::SemverParts)
        expect(result.major).to eq(1)
        expect(result.minor).to eq(2)
        expect(result.patch).to eq(3)
      end

      it "returns nil when semver_parts returns nil" do
        version = version_with_semver_parts.new(nil, "invalid")

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

    context "with relaxed mode (default)" do
      it "treats 0.y.z minor bumps as minor" do
        prev_version = DummyPackageManager::Version.new("0.2.3")
        curr_version = DummyPackageManager::Version.new("0.3.0")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "relaxed")).to eq("minor")
      end

      it "treats 0.0.z patch bumps as patch" do
        prev_version = DummyPackageManager::Version.new("0.0.3")
        curr_version = DummyPackageManager::Version.new("0.0.4")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "relaxed")).to eq("patch")
      end
    end

    context "with strict mode" do
      it "treats 0.y.z minor bumps as major" do
        prev_version = DummyPackageManager::Version.new("0.2.3")
        curr_version = DummyPackageManager::Version.new("0.3.0")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("major")
      end

      it "treats 0.y.z patch bumps as patch" do
        prev_version = DummyPackageManager::Version.new("0.2.3")
        curr_version = DummyPackageManager::Version.new("0.2.4")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("patch")
      end

      it "treats 0.0.z patch bumps as major" do
        prev_version = DummyPackageManager::Version.new("0.0.3")
        curr_version = DummyPackageManager::Version.new("0.0.4")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("major")
      end

      it "treats 0.0.z minor bumps as major" do
        prev_version = DummyPackageManager::Version.new("0.0.3")
        curr_version = DummyPackageManager::Version.new("0.1.0")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("major")
      end

      it "treats 1.y.z minor bumps as minor (standard semver)" do
        prev_version = DummyPackageManager::Version.new("1.2.3")
        curr_version = DummyPackageManager::Version.new("1.3.0")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("minor")
      end

      it "treats 1.y.z major bumps as major (standard semver)" do
        prev_version = DummyPackageManager::Version.new("1.2.3")
        curr_version = DummyPackageManager::Version.new("2.0.0")

        expect(helper.classify_semver_update(prev_version, curr_version, semantic_versioning: "strict")).to eq("major")
      end
    end
  end

  describe "#classify_strict_semver" do
    let(:prev_parts) { Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 2, patch: 3) }
    let(:curr_parts) { Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 3, patch: 0) }

    before do
      allow(Dependabot).to receive(:logger).and_return(instance_double(Logger, info: nil))
    end

    it "classifies 0.y.z to 0.y+1.z as major" do
      prev = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 11, patch: 5)
      curr = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 12, patch: 0)

      expect(helper.classify_strict_semver(prev, curr)).to eq("major")
    end

    it "classifies 0.0.z to 0.0.z+1 as major" do
      prev = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 0, patch: 3)
      curr = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 0, patch: 4)

      expect(helper.classify_strict_semver(prev, curr)).to eq("major")
    end

    it "classifies 0.y.z to 0.y.z+1 as patch" do
      prev = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 2, patch: 3)
      curr = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 0, minor: 2, patch: 4)

      expect(helper.classify_strict_semver(prev, curr)).to eq("patch")
    end

    it "classifies 1.y.z to 1.y+1.z as minor" do
      prev = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 1, minor: 2, patch: 3)
      curr = Dependabot::Updater::UpdateTypeHelper::SemverParts.new(major: 1, minor: 3, patch: 0)

      expect(helper.classify_strict_semver(prev, curr)).to eq("minor")
    end
  end
end
