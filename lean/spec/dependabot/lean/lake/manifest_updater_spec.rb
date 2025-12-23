# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/lean/lake/manifest_updater"

RSpec.describe Dependabot::Lean::Lake::ManifestUpdater do
  let(:updater) do
    described_class.new(
      manifest_content: manifest_content,
      dependencies: dependencies
    )
  end

  let(:manifest_content) do
    fixture("projects", "lake_project", "lake-manifest.json")
  end

  describe "#updated_manifest_content" do
    context "when updating a single dependency" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "batteries",
            version: "abc123def456789012345678901234567890abcd",
            previous_version: "dff865b7ee7011518d59abfc101c368293173150",
            requirements: [{
              requirement: nil,
              file: "lake-manifest.json",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/leanprover-community/batteries",
                ref: "main",
                branch: "main"
              }
            }],
            package_manager: "lean"
          )
        ]
      end

      it "updates the rev field for the dependency" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        batteries = parsed["packages"].find { |p| p["name"] == "batteries" }
        expect(batteries["rev"]).to eq("abc123def456789012345678901234567890abcd")
      end

      it "preserves other packages unchanged" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        aesop = parsed["packages"].find { |p| p["name"] == "aesop" }
        expect(aesop["rev"]).to eq("fa78cf032194308a950a264ed87b422a2a7c1c6c")
      end

      it "preserves other fields in the manifest" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        expect(parsed["version"]).to eq("1.1.0")
        expect(parsed["name"]).to eq("test-project")
      end
    end

    context "when updating multiple dependencies" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "batteries",
            version: "new_batteries_sha",
            previous_version: "dff865b7ee7011518d59abfc101c368293173150",
            requirements: [],
            package_manager: "lean"
          ),
          Dependabot::Dependency.new(
            name: "aesop",
            version: "new_aesop_sha",
            previous_version: "fa78cf032194308a950a264ed87b422a2a7c1c6c",
            requirements: [],
            package_manager: "lean"
          )
        ]
      end

      it "updates all specified dependencies" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        batteries = parsed["packages"].find { |p| p["name"] == "batteries" }
        aesop = parsed["packages"].find { |p| p["name"] == "aesop" }

        expect(batteries["rev"]).to eq("new_batteries_sha")
        expect(aesop["rev"]).to eq("new_aesop_sha")
      end
    end

    context "when the dependency is not in the manifest" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "nonexistent",
            version: "some_sha",
            previous_version: "old_sha",
            requirements: [],
            package_manager: "lean"
          )
        ]
      end

      it "does not modify the manifest" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        batteries = parsed["packages"].find { |p| p["name"] == "batteries" }
        expect(batteries["rev"]).to eq("dff865b7ee7011518d59abfc101c368293173150")
      end
    end

    context "when version hasn't changed" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "batteries",
            version: "dff865b7ee7011518d59abfc101c368293173150",
            previous_version: "dff865b7ee7011518d59abfc101c368293173150",
            requirements: [],
            package_manager: "lean"
          )
        ]
      end

      it "does not modify the rev" do
        result = updater.updated_manifest_content
        parsed = JSON.parse(result)

        batteries = parsed["packages"].find { |p| p["name"] == "batteries" }
        expect(batteries["rev"]).to eq("dff865b7ee7011518d59abfc101c368293173150")
      end
    end
  end
end
