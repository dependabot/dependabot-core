# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/update_checker/requirements_updater"

RSpec.describe Dependabot::Bazel::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version
    )
  end

  let(:latest_version) { "0.57.0" }

  describe "#updated_requirements" do
    context "with a single requirement" do
      let(:requirements) do
        [{
          file: "MODULE.bazel",
          requirement: "0.33.0",
          groups: [],
          source: nil
        }]
      end

      it "updates the requirement to the latest version" do
        updated = updater.updated_requirements

        expect(updated).to eq(
          [{
            file: "MODULE.bazel",
            requirement: "0.57.0",
            groups: [],
            source: nil
          }]
        )
      end

      it "preserves other requirement attributes" do
        updated = updater.updated_requirements

        expect(updated.first[:file]).to eq("MODULE.bazel")
        expect(updated.first[:groups]).to eq([])
        expect(updated.first[:source]).to be_nil
      end
    end

    context "with multiple requirements" do
      let(:requirements) do
        [
          {
            file: "MODULE.bazel",
            requirement: "0.33.0",
            groups: [],
            source: nil
          },
          {
            file: "other/MODULE.bazel",
            requirement: "0.34.0",
            groups: ["dev"],
            source: { type: "git" }
          }
        ]
      end

      it "updates all requirements to the latest version" do
        updated = updater.updated_requirements

        expect(updated).to eq(
          [
            {
              file: "MODULE.bazel",
              requirement: "0.57.0",
              groups: [],
              source: nil
            },
            {
              file: "other/MODULE.bazel",
              requirement: "0.57.0",
              groups: ["dev"],
              source: { type: "git" }
            }
          ]
        )
      end

      it "preserves individual requirement attributes" do
        updated = updater.updated_requirements

        expect(updated[0][:file]).to eq("MODULE.bazel")
        expect(updated[0][:groups]).to eq([])
        expect(updated[0][:source]).to be_nil

        expect(updated[1][:file]).to eq("other/MODULE.bazel")
        expect(updated[1][:groups]).to eq(["dev"])
        expect(updated[1][:source]).to eq({ type: "git" })
      end
    end

    context "with empty requirements" do
      let(:requirements) { [] }

      it "returns empty array" do
        expect(updater.updated_requirements).to eq([])
      end
    end

    context "with complex requirement attributes" do
      let(:requirements) do
        [{
          file: "MODULE.bazel",
          requirement: "0.33.0",
          groups: %w(main test),
          source: {
            type: "registry",
            url: "https://registry.bazel.build",
            metadata: { yanked: false }
          },
          metadata: {
            property_name: "rules_go_version",
            property_source: "MODULE.bazel"
          }
        }]
      end

      it "preserves all attributes while updating version" do
        updated = updater.updated_requirements

        expect(updated).to eq(
          [{
            file: "MODULE.bazel",
            requirement: "0.57.0",
            groups: %w(main test),
            source: {
              type: "registry",
              url: "https://registry.bazel.build",
              metadata: { yanked: false }
            },
            metadata: {
              property_name: "rules_go_version",
              property_source: "MODULE.bazel"
            }
          }]
        )
      end
    end

    context "when requirements are modified after creation" do
      let(:requirements) do
        [{
          file: "MODULE.bazel",
          requirement: "0.33.0",
          groups: [],
          source: nil
        }]
      end

      it "does not affect the original requirements" do
        original_requirements = requirements.dup
        updater.updated_requirements

        expect(requirements).to eq(original_requirements)
      end

      it "creates independent copies" do
        updated = updater.updated_requirements
        updated.first[:requirement] = "modified"

        fresh_updated = updater.updated_requirements

        expect(fresh_updated.first[:requirement]).to eq("0.57.0")
      end
    end
  end
end
