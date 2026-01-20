# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/update_type_helper"

RSpec.describe Dependabot::Updater::UpdateTypeHelper do
  # Create a test class that includes the module
  let(:helper_class) do
    Class.new do
      include Dependabot::Updater::UpdateTypeHelper
    end
  end

  let(:helper) { helper_class.new }

  describe "#semver_parts" do
    context "when version responds to semver_parts" do
      it "returns SemverParts from the version's semver_parts method" do
        version = instance_double(Version, semver_parts: [1, 2, 3])

        result = helper.semver_parts(version)

        expect(result).to be_a(Dependabot::Updater::UpdateTypeHelper::SemverParts)
        expect(result.major).to eq(1)
        expect(result.minor).to eq(2)
        expect(result.patch).to eq(3)
      end

      it "returns nil when semver_parts returns nil" do
        version = instance_double(Version, semver_parts: nil, to_s: "invalid")
        allow(version).to receive(:respond_to?).with(:semver_parts).and_return(true)

        result = helper.semver_parts(version)

        expect(result).to be_nil
      end
    end

    context "when version is parsed from string" do
      context "with standard semver format" do
        it "returns SemverParts for '1.2.3'" do
          version = instance_double(Version, to_s: "1.2.3")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(3)
        end

        it "returns SemverParts with zero defaults for partial versions" do
          version = instance_double(Version, to_s: "1")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end

        it "handles two-part versions" do
          version = instance_double(Version, to_s: "1.2")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(2)
          expect(result.patch).to eq(0)
        end
      end

      context "with 'v' prefix" do
        it "strips 'v' prefix and extracts numeric parts for 'v1.0.0'" do
          version = instance_double(Version, to_s: "v1.0.0")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(0)
          expect(result.patch).to eq(0)
        end

        it "strips 'v' prefix and extracts numeric parts for 'v1.1.1'" do
          version = instance_double(Version, to_s: "v1.1.1")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(1)
          expect(result.minor).to eq(1)
          expect(result.patch).to eq(1)
        end

        it "handles v2.3.4 correctly" do
          version = instance_double(Version, to_s: "v2.3.4")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result.major).to eq(2)
          expect(result.minor).to eq(3)
          expect(result.patch).to eq(4)
        end
      end

      context "with non-numeric segments" do
        it "returns nil when all segments are non-numeric" do
          version = instance_double(Version, to_s: "alpha.beta.gamma")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end

      context "with empty string" do
        it "returns nil for empty string" do
          version = instance_double(Version, to_s: "")
          allow(version).to receive(:respond_to?).with(:semver_parts).and_return(false)

          result = helper.semver_parts(version)

          expect(result).to be_nil
        end
      end
    end
  end

  describe "#classify_semver_update" do
    let(:prev_version) { instance_double(Version) }
    let(:curr_version) { instance_double(Version) }

    before do
      allow(prev_version).to receive(:respond_to?).with(:semver_parts).and_return(false)
      allow(curr_version).to receive(:respond_to?).with(:semver_parts).and_return(false)
      allow(Dependabot).to receive(:logger).and_return(instance_double(Logger, info: nil))
    end

    it "returns 'major' for major version bump" do
      allow(prev_version).to receive(:to_s).and_return("1.0.0")
      allow(curr_version).to receive(:to_s).and_return("2.0.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end

    it "returns 'minor' for minor version bump" do
      allow(prev_version).to receive(:to_s).and_return("1.0.0")
      allow(curr_version).to receive(:to_s).and_return("1.1.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("minor")
    end

    it "returns 'patch' for patch version bump" do
      allow(prev_version).to receive(:to_s).and_return("1.0.0")
      allow(curr_version).to receive(:to_s).and_return("1.0.1")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("patch")
    end

    it "handles versions with 'v' prefix correctly" do
      allow(prev_version).to receive(:to_s).and_return("v1.0.0")
      allow(curr_version).to receive(:to_s).and_return("v2.0.0")

      expect(helper.classify_semver_update(prev_version, curr_version)).to eq("major")
    end

    it "returns nil when versions cannot be parsed" do
      allow(prev_version).to receive(:to_s).and_return("alpha")
      allow(curr_version).to receive(:to_s).and_return("beta")

      expect(helper.classify_semver_update(prev_version, curr_version)).to be_nil
    end
  end
end
