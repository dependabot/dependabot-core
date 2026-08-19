# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/package_json_preparer"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PackageJsonPreparer do
  describe "#prepared_content" do
    it "does not craash when finding null dependencies" do
      original_content = fixture("projects", "generic", "null_deps", "package.json")

      preparer = described_class.new(package_json_content: original_content)

      expect(preparer.prepared_content).to eq(original_content)
    end
  end

  describe "#remove_dev_engines" do
    let(:preparer) { described_class.new(package_json_content: package_json_content) }

    context "when package.json contains devEngines with array format" do
      let(:package_json_content) do
        <<~JSON
          {
            "name": "test",
            "version": "1.0.0",
            "devEngines": {
              "runtime": {
                "name": "node",
                "version": "^18 || ^20 || ^22",
                "onFail": "warn"
              },
              "packageManager": [
                {
                  "name": "npm",
                  "version": "^10 || ^11",
                  "onFail": "warn"
                }
              ]
            },
            "dependencies": {
              "express": "^4.17.1"
            }
          }
        JSON
      end

      it "removes devEngines field" do
        result = JSON.parse(preparer.send(:remove_dev_engines, package_json_content))
        expect(result).not_to have_key("devEngines")
        expect(result).to have_key("dependencies")
        expect(result["name"]).to eq("test")
      end
    end

    context "when package.json contains devEngines with object format" do
      let(:package_json_content) do
        <<~JSON
          {
            "name": "test",
            "version": "1.0.0",
            "devEngines": {
              "runtime": {
                "name": "node",
                "version": "^18.0.0"
              },
              "packageManager": {
                "name": "npm",
                "version": "^10.0.0"
              }
            },
            "dependencies": {
              "express": "^4.17.1"
            }
          }
        JSON
      end

      it "removes devEngines field" do
        result = JSON.parse(preparer.send(:remove_dev_engines, package_json_content))
        expect(result).not_to have_key("devEngines")
        expect(result).to have_key("dependencies")
      end
    end

    context "when package.json does not contain devEngines" do
      let(:package_json_content) do
        <<~JSON
          {
            "name": "test",
            "version": "1.0.0",
            "dependencies": {
              "express": "^4.17.1"
            }
          }
        JSON
      end

      it "returns content unchanged" do
        result = JSON.parse(preparer.send(:remove_dev_engines, package_json_content))
        expect(result).not_to have_key("devEngines")
        expect(result).to have_key("dependencies")
      end
    end

    context "when package.json is invalid JSON" do
      let(:package_json_content) { "{ invalid json }" }

      it "returns content unchanged" do
        result = preparer.send(:remove_dev_engines, package_json_content)
        expect(result).to eq(package_json_content)
      end
    end
  end
end

