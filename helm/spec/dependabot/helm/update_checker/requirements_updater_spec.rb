# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/requirements_update_strategy"
require "dependabot/helm/update_checker/requirements_updater"

RSpec.describe Dependabot::Helm::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      update_strategy: update_strategy,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) do
    [{
      file: "Chart.yaml",
      requirement: chart_req,
      groups: [],
      source: { tag: "x" },
      metadata: { type: :helm_chart }
    }]
  end
  let(:chart_req) { "^1.0.0" }
  let(:latest_resolvable_version) { "1.0.5" }
  let(:updated_req) { updater.updated_requirements.first[:requirement] }

  describe "#updated_requirements" do
    context "with BumpVersions (increase)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      it "bumps the caret floor" do
        expect(updated_req).to eq("^1.0.5")
      end

      context "with an exact pin" do
        let(:chart_req) { "1.0.0" }

        it "pins to the new version (current behavior)" do
          expect(updated_req).to eq("1.0.5")
        end
      end
    end

    context "with BumpVersionsIfNecessary (increase-if-necessary)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

      context "when the new version is already in range" do
        let(:latest_resolvable_version) { "1.0.5" }

        it "leaves the requirement unchanged" do
          expect(updated_req).to eq("^1.0.0")
        end
      end

      context "when the new version is out of range" do
        let(:latest_resolvable_version) { "2.0.0" }

        it "bumps the constraint" do
          expect(updated_req).to eq("^2.0.0")
        end
      end
    end

    context "with WidenRanges (widen)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

      context "when in range" do
        let(:latest_resolvable_version) { "1.0.5" }

        it "leaves the caret unchanged" do
          expect(updated_req).to eq("^1.0.0")
        end
      end

      context "when out of range" do
        let(:chart_req) { "^0.8.0" }
        let(:latest_resolvable_version) { "1.5.0" }

        it "bumps the caret (npm widen semantics)" do
          expect(updated_req).to eq("^1.5.0")
        end
      end

      context "with a < bound" do
        let(:chart_req) { "< 1.2.0" }
        let(:latest_resolvable_version) { "1.5.0" }

        it "widens the upper bound in place" do
          expect(updated_req).to eq("< 1.6.0")
        end
      end
    end

    context "when there is no resolvable version" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { nil }

      it "leaves the requirement unchanged" do
        expect(updated_req).to eq("^1.0.0")
      end
    end
  end
end
