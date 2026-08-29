# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/update_checker/requirements_updater"

RSpec.describe Dependabot::Powershell::UpdateChecker::RequirementsUpdater do
  subject(:updater) do
    described_class.new(
      requirements: requirements,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:latest_resolvable_version) { "2.5.0" }

  def requirement(requirement_string, version_key:, style: :hashtable)
    {
      requirement: requirement_string,
      groups: [],
      source: { type: "registry", url: "https://www.powershellgallery.com/api/v2" },
      file: "module.psd1",
      metadata: { version_key: version_key, style: style }
    }
  end

  describe "#updated_requirements" do
    context "when there is no latest resolvable version" do
      let(:latest_resolvable_version) { nil }
      let(:requirements) { [requirement("= 1.0.0", version_key: "RequiredVersion")] }

      it "returns the requirements unchanged" do
        expect(updater.updated_requirements).to eq(requirements)
      end
    end

    context "when the requirement has no version constraint" do
      let(:requirements) do
        [{ requirement: nil, groups: [], source: nil, file: "module.psd1", metadata: {} }]
      end

      it "leaves the unconstrained requirement unchanged" do
        expect(updater.updated_requirements).to eq(requirements)
      end
    end

    context "when the requirement is an exact RequiredVersion pin" do
      let(:requirements) { [requirement("= 1.0.0", version_key: "RequiredVersion")] }

      it "bumps the pin to the latest resolvable version" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq("= 2.5.0")
      end

      it "preserves the metadata for the file updater stage" do
        updated = updater.updated_requirements.first
        expect(updated[:metadata]).to eq(version_key: "RequiredVersion", style: :hashtable)
      end

      it "preserves the source, groups and file" do
        updated = updater.updated_requirements.first
        expect(updated[:source]).to eq(requirements.first[:source])
        expect(updated[:groups]).to eq([])
        expect(updated[:file]).to eq("module.psd1")
      end
    end

    context "when the requirement is a ModuleVersion minimum" do
      let(:requirements) { [requirement(">= 1.0.0", version_key: "ModuleVersion")] }

      it "bumps the minimum constraint to track the latest resolvable version" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq(">= 2.5.0")
      end
    end

    context "when a ModuleVersion minimum is unsatisfied because the latest resolvable version is " \
            "below the declared floor" do
      let(:requirements) { [requirement(">= 2.0.0", version_key: "ModuleVersion")] }
      let(:latest_resolvable_version) { "1.5.0" }

      it "leaves the floor unchanged instead of opening a requirement downgrade" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq(">= 2.0.0")
      end
    end

    context "when the requirement is a MaximumVersion cap" do
      let(:requirements) { [requirement("<= 1.0.0", version_key: "MaximumVersion")] }

      it "raises the cap to the latest resolvable version" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq("<= 2.5.0")
      end
    end

    context "when the requirement is a ModuleVersion+MaximumVersion range" do
      let(:requirements) { [requirement(">= 1.0.0, <= 1.5.0", version_key: "ModuleVersion+MaximumVersion")] }

      it "keeps the declared lower bound and raises only the upper bound" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq(">= 1.0.0, <= 2.5.0")
      end
    end

    context "when a ModuleVersion+MaximumVersion range is unsatisfied because the latest version is " \
            "below the declared lower bound" do
      let(:requirements) { [requirement(">= 2.0.0, <= 3.0.0", version_key: "ModuleVersion+MaximumVersion")] }
      let(:latest_resolvable_version) { "1.5.0" }

      it "leaves the range unchanged instead of producing an impossible range" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq(">= 2.0.0, <= 3.0.0")
      end
    end

    context "when the requirement already permits the latest resolvable version" do
      let(:requirements) { [requirement("<= 5.0.0", version_key: "MaximumVersion")] }
      let(:latest_resolvable_version) { "1.2.0" }

      it "leaves the requirement unchanged" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq("<= 5.0.0")
      end
    end

    context "when the exact pin already matches the latest resolvable version" do
      let(:requirements) { [requirement("= 2.5.0", version_key: "RequiredVersion")] }

      it "leaves the requirement unchanged" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq("= 2.5.0")
      end
    end

    context "when an exact pin differs from the latest version only by leading zeroes" do
      let(:requirements) { [requirement("= 01.02", version_key: "RequiredVersion")] }
      let(:latest_resolvable_version) { "1.2" }

      it "leaves the equivalent declaration unchanged" do
        expect(updater.updated_requirements).to eq(requirements)
      end
    end

    context "when a maximum has fewer components than the latest version" do
      let(:requirements) { [requirement("<= 1.2", version_key: "MaximumVersion")] }
      let(:latest_resolvable_version) { "1.2.0" }

      it "raises the maximum because the unspecified component is older than zero" do
        updated = updater.updated_requirements.first
        expect(updated[:requirement]).to eq("<= 1.2.0")
      end
    end

    context "with multiple requirements for the same dependency" do
      let(:requirements) do
        [
          requirement("= 1.0.0", version_key: "RequiredVersion", style: :string),
          requirement(">= 1.0.0", version_key: "ModuleVersion", style: :hashtable)
        ]
      end

      it "updates each requirement independently" do
        updated = updater.updated_requirements
        expect(updated[0][:requirement]).to eq("= 2.5.0")
        expect(updated[0][:metadata][:style]).to eq(:string)
        # ModuleVersion minimums always track the latest resolvable version.
        expect(updated[1][:requirement]).to eq(">= 2.5.0")
        expect(updated[1][:metadata][:style]).to eq(:hashtable)
      end
    end
  end
end
