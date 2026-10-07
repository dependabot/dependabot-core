# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/npm_package_manager_config"

RSpec.describe Dependabot::Package::NpmPackageManagerConfig do
  describe ".from_package_json" do
    subject(:config) { described_class.from_package_json(package_json) }

    let(:package_json) do
      {
        "packageManager" => "pnpm@10.11",
        "engines" => {
          "node" => ">=20",
          "pnpm" => ">=10 || >=7 <9",
          "custom" => "unchanged"
        },
        "private" => true
      }
    end

    it "parses package-manager metadata without normalizing it" do
      expect(config).to have_attributes(
        package_manager: "pnpm@10.11",
        engines: {
          "node" => ">=20",
          "pnpm" => ">=10 || >=7 <9",
          "custom" => "unchanged"
        }
      )
    end

    context "with missing known fields" do
      let(:package_json) { { "name" => "example" } }

      it "uses nil defaults" do
        expect(config).to have_attributes(package_manager: nil, engines: nil)
      end
    end

    context "with a nil manifest" do
      let(:package_json) { nil }

      it "uses nil defaults" do
        expect(config).to have_attributes(package_manager: nil, engines: nil)
      end
    end

    context "with null known fields" do
      let(:package_json) { { "packageManager" => nil, "engines" => nil } }

      it "uses nil defaults" do
        expect(config).to have_attributes(package_manager: nil, engines: nil)
      end
    end

    context "with an empty engines object" do
      let(:package_json) { { "engines" => {} } }

      it "preserves the empty object" do
        expect(config.engines).to eq({})
      end
    end

    context "with null engine requirements" do
      let(:package_json) do
        {
          "engines" => {
            "npm" => nil,
            "node" => ">=20"
          }
        }
      end

      it "drops the null entries" do
        expect(config.engines).to eq("node" => ">=20")
      end
    end

    [
      [[], "package.json must be an object"],
      [{ packageManager: "npm@11" }, "package.json keys must be strings"],
      [{ "packageManager" => 11 }, "packageManager must be a string"],
      [{ "engines" => [] }, "engines must be an object"],
      [{ "engines" => { npm: ">=11" } }, "engines keys must be strings"],
      [{ "engines" => { "npm" => 11 } }, "engines.npm must be a string"],
      [{ "engines" => { "npm" => true } }, "engines.npm must be a string"]
    ].each do |invalid_package_json, message|
      context "with #{message}" do
        let(:package_json) { invalid_package_json }

        it "raises an explicit type error" do
          expect { config }.to raise_error(TypeError, message)
        end
      end
    end
  end
end
