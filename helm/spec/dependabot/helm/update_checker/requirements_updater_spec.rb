# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_requirement"
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
    [Dependabot::DependencyRequirement.create(
      file: "Chart.yaml",
      requirement: chart_req,
      groups: [],
      source: { tag: "x" },
      metadata: { type: :helm_chart }
    )]
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

    context "with a tilde requirement" do
      let(:chart_req) { "~1.2.0" }

      context "with BumpVersionsIfNecessary, in range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }
        let(:latest_resolvable_version) { "1.2.9" }

        it "leaves it unchanged" do
          expect(updated_req).to eq("~1.2.0")
        end
      end

      context "with BumpVersionsIfNecessary, out of range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }
        let(:latest_resolvable_version) { "1.3.0" }

        it "bumps the tilde" do
          expect(updated_req).to eq("~1.3.0")
        end
      end

      context "with WidenRanges, out of range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }
        let(:latest_resolvable_version) { "1.3.0" }

        it "bumps the tilde (npm widen semantics)" do
          expect(updated_req).to eq("~1.3.0")
        end
      end
    end

    context "with an explicit comparator range" do
      let(:chart_req) { ">=1.0.0 <2.0.0" }

      context "with BumpVersionsIfNecessary, in range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }
        let(:latest_resolvable_version) { "1.5.0" }

        it "leaves it unchanged" do
          expect(updated_req).to eq(">=1.0.0 <2.0.0")
        end
      end

      context "with WidenRanges, out of range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }
        let(:latest_resolvable_version) { "2.5.0" }

        it "widens the upper bound in place" do
          expect(updated_req).to eq(">=1.0.0 <3.0.0")
        end
      end

      context "with a comma-separated range (Masterminds comma-AND)" do
        let(:chart_req) { ">=1.0.0,<2.0.0" }
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }
        let(:latest_resolvable_version) { "2.5.0" }

        it "widens while preserving the comma form" do
          expect(updated_req).to eq(">=1.0.0,<3.0.0")
        end
      end
    end

    context "with an OR range that is already satisfied" do
      let(:chart_req) { "^1.0.0 || ^2.0.0" }
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }
      let(:latest_resolvable_version) { "2.5.0" }

      it "leaves it unchanged" do
        expect(updated_req).to eq("^1.0.0 || ^2.0.0")
      end
    end

    context "with an OR range where a later alternative permits the version (BumpVersions)" do
      # Exercises the any?-over-alternatives check: the first alternative (<1.0.0)
      # does not permit 2.5.0, but the second (>=2.0.0) does, so no change.
      let(:chart_req) { "<1.0.0 || >=2.0.0" }
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { "2.5.0" }

      it "leaves it unchanged" do
        expect(updated_req).to eq("<1.0.0 || >=2.0.0")
      end
    end

    context "with an OR range where no alternative permits the version" do
      let(:chart_req) { "^0.5.0 || ^1.0.0" }
      let(:latest_resolvable_version) { "3.0.0" }

      context "with WidenRanges" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

        it "adds a new alternative (npm widen semantics)" do
          expect(updated_req).to eq("^0.5.0 || ^1.0.0 || ^3.0.0")
        end
      end

      context "with BumpVersions" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

        it "collapses to the bumped first alternative" do
          expect(updated_req).to eq("^3.0.0")
        end
      end
    end

    context "with a hyphen range" do
      let(:chart_req) { "1.0.0 - 1.4.0" }

      context "with BumpVersions, out of range" do
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
        let(:latest_resolvable_version) { "1.6.0" }

        it "widens the upper bound to permit the version" do
          expect(updated_req).to eq("1.0.0 - 1.7.0")
        end
      end

      context "with BumpVersionsIfNecessary, in range" do
        let(:chart_req) { "1.0.0 - 2.0.0" }
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }
        let(:latest_resolvable_version) { "1.5.0" }

        it "leaves it unchanged" do
          expect(updated_req).to eq("1.0.0 - 2.0.0")
        end
      end
    end

    context "with a prerelease constraint (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { "1.5.0" }

      context "with a caret prerelease" do
        let(:chart_req) { "^1.2.3-rc1" }

        it "bumps to the release caret" do
          expect(updated_req).to eq("^1.5.0")
        end
      end

      context "with an exact prerelease pin" do
        let(:chart_req) { "1.2.3-rc1" }

        it "bumps to the release version" do
          expect(updated_req).to eq("1.5.0")
        end
      end
    end

    context "with an x-range (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { "4.5.0" }

      context "with a lowercase wildcard" do
        let(:chart_req) { "1.x" }

        it "bumps the major while preserving the wildcard" do
          expect(updated_req).to eq("4.x")
        end
      end

      context "with an uppercase wildcard" do
        let(:chart_req) { "1.X" }

        it "preserves the authored uppercase wildcard" do
          expect(updated_req).to eq("4.X")
        end
      end
    end

    context "with a prerelease upper bound in a range (WidenRanges)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }
      let(:chart_req) { ">=1.0.0 <2.0.0-rc1" }
      let(:latest_resolvable_version) { "2.5.0" }

      it "widens without leaving a stale prerelease suffix" do
        expect(updated_req).to eq(">=1.0.0 <3.0.0")
      end
    end

    context "with build metadata / digest (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "when the old constraint carries a stale digest" do
        let(:chart_req) { "1.2.3+old" }
        let(:latest_resolvable_version) { "1.5.0" }

        it "replaces the whole version, dropping the stale suffix" do
          expect(updated_req).to eq("1.5.0")
        end
      end

      context "when the latest version carries a digest" do
        let(:chart_req) { "1.2.3" }
        let(:latest_resolvable_version) { "1.5.0+new" }

        it "adopts the new digest" do
          expect(updated_req).to eq("1.5.0+new")
        end
      end

      context "with a caret constraint carrying a stale digest" do
        let(:chart_req) { "^1.2.3+old" }
        let(:latest_resolvable_version) { "1.5.0" }

        it "bumps the caret floor without the stale suffix" do
          expect(updated_req).to eq("^1.5.0")
        end
      end
    end

    context "with a != exclusion constraint (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { "2.0.0" }

      context "when the latest version is already permitted" do
        let(:chart_req) { "!=1.0.0" }

        it "leaves it unchanged (does not rewrite the excluded version)" do
          expect(updated_req).to eq("!=1.0.0")
        end
      end

      context "when != is part of a compound constraint" do
        let(:chart_req) { ">=1.0.0 !=1.5.0" }

        it "preserves the whole constraint" do
          expect(updated_req).to eq(">=1.0.0 !=1.5.0")
        end
      end
    end

    context "with a strict lower-bound (>) constraint (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:chart_req) { ">1.0.0" }
      let(:latest_resolvable_version) { "2.0.0" }

      it "leaves it unchanged (rewriting would exclude the target)" do
        expect(updated_req).to eq(">1.0.0")
      end
    end

    context "with a comma-AND exclusion plus an upper bound (BumpVersions)" do
      # The upper bound to widen is the < operand, not the numerically-largest
      # token (the != operand is larger here).
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:chart_req) { "!=9.0.0,<2.0.0" }
      let(:latest_resolvable_version) { "2.0.0" }

      it "widens the < bound and leaves the exclusion intact" do
        expect(updated_req).to eq("!=9.0.0,<3.0.0")
      end
    end

    context "when there is no resolvable version" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { nil }

      it "leaves the requirement unchanged" do
        expect(updated_req).to eq("^1.0.0")
      end
    end

    context "with LockfileOnly" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }
      let(:chart_req) { "^1.0.0" }
      let(:latest_resolvable_version) { "2.0.0" }

      it "leaves the requirement unchanged" do
        expect(updated_req).to eq("^1.0.0")
      end
    end

    context "with a dist-tag / non-numeric constraint" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:chart_req) { "stable" }
      let(:latest_resolvable_version) { "2.0.0" }

      it "leaves it untouched" do
        expect(updated_req).to eq("stable")
      end
    end

    context "when the latest version has fewer segments than the constraint" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:latest_resolvable_version) { "4.5" }

      context "with an x-range" do
        let(:chart_req) { "1.2.x" }

        it "preserves the wildcard rather than dropping it" do
          expect(updated_req).to eq("4.5.x")
        end
      end

      context "with a widened upper bound" do
        let(:chart_req) { ">=1.0.0 <1.2.3" }
        let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

        it "does not raise" do
          expect { updated_req }.not_to raise_error
        end
      end
    end

    context "with an empty constraint (BumpVersions)" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
      let(:chart_req) { "" }
      let(:latest_resolvable_version) { "1.5.0" }

      it "leaves it unchanged without raising" do
        expect(updated_req).to eq("")
      end
    end
  end
end
