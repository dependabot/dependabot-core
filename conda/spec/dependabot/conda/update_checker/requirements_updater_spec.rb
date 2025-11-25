# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker/requirements_updater"
require "dependabot/requirements_update_strategy"

RSpec.describe Dependabot::Conda::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      update_strategy: update_strategy,
      latest_resolvable_version: latest_version
    )
  end

  let(:latest_version) { "2.3.4" }

  describe "#updated_requirements" do
    context "with BumpVersions strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "with wildcard requirement" do
        let(:requirements) do
          [{ requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "preserves wildcard pattern at new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.*")
        end
      end

      context "with pip-style wildcard requirement" do
        let(:requirements) do
          [{ requirement: "==1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "preserves wildcard pattern at new version with pip operator" do
          expect(updater.updated_requirements.first[:requirement]).to eq("==2.3.*")
        end
      end

      context "with exact conda requirement" do
        let(:requirements) do
          [{ requirement: "=1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "bumps to exact new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.4")
        end
      end

      context "with exact pip requirement" do
        let(:requirements) do
          [{ requirement: "==1.26", groups: ["pip"], source: nil, file: "environment.yml" }]
        end

        it "bumps to exact new version with pip operator" do
          expect(updater.updated_requirements.first[:requirement]).to eq("==2.3.4")
        end
      end

      context "with >= requirement" do
        let(:requirements) do
          [{ requirement: ">=1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "updates to new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=2.3.4")
        end

        context "when requirement version is too high" do
          let(:requirements) do
            [{ requirement: ">=5.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
          end

          it "returns unfixable" do
            expect(updater.updated_requirements.first[:requirement]).to eq(:unfixable)
          end
        end
      end

      context "with compatible release requirement" do
        let(:requirements) do
          [{ requirement: "~=1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "updates compatible release version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("~=2.3.4")
        end
      end

      context "with major wildcard" do
        let(:requirements) do
          [{ requirement: "=1.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "preserves major wildcard pattern" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.*")
        end
      end

      context "with > requirement" do
        let(:requirements) do
          [{ requirement: ">1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "updates to new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">2.3.4")
        end
      end

      context "with <= requirement" do
        let(:requirements) do
          [{ requirement: "<=2.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps the original requirement unchanged" do
          expect(updater.updated_requirements.first[:requirement]).to eq("<=2.0")
        end
      end

      context "with < requirement" do
        let(:requirements) do
          [{ requirement: "<3.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps the original requirement unchanged" do
          expect(updater.updated_requirements.first[:requirement]).to eq("<3.0")
        end
      end

      context "with != requirement" do
        let(:requirements) do
          [{ requirement: "!=1.5", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps the original requirement unchanged" do
          expect(updater.updated_requirements.first[:requirement]).to eq("!=1.5")
        end
      end

      context "with whitespace in exact requirement" do
        let(:requirements) do
          [{ requirement: "= 1.21", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "preserves operator but updates version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.4")
        end
      end

      context "with whitespace in pip requirement" do
        let(:requirements) do
          [{ requirement: "== 1.21", groups: ["pip"], source: nil, file: "environment.yml" }]
        end

        it "preserves operator but updates version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("==2.3.4")
        end
      end

      context "with requirement version having fewer digits" do
        let(:requirements) do
          [{ requirement: "=1.4", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "uses full precision of new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.4")
        end
      end

      context "with requirement version having more digits" do
        let(:requirements) do
          [{ requirement: "=1.21.0.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "uses full precision of new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.4")
        end
      end

      context "when requirement version is too high" do
        let(:requirements) do
          [{ requirement: ">=5.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "returns unfixable" do
          expect(updater.updated_requirements.first[:requirement]).to eq(:unfixable)
        end
      end

      context "with comma-separated range requirement" do
        let(:requirements) do
          [{ requirement: ">=3.10,<3.12", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end
        let(:latest_version) { "3.14.0" }

        it "keeps satisfied lower bound and updates unsatisfied upper bound" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=3.10,<3.15.0")
        end
      end

      context "with range where new version satisfies both bounds" do
        let(:requirements) do
          [{ requirement: ">=2.0,<5.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps entire requirement unchanged" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=2.0,<5.0")
        end
      end

      context "with range where lower bound is too high" do
        let(:requirements) do
          [{ requirement: ">=5.0,<6.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "returns unfixable" do
          expect(updater.updated_requirements.first[:requirement]).to eq(:unfixable)
        end
      end

      context "with range where lower bound doesn't satisfy new version" do
        let(:requirements) do
          [{ requirement: ">=2.5,<3.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end
        let(:latest_version) { "2.3.4" }

        it "returns unfixable (cannot lower minimum version)" do
          expect(updater.updated_requirements.first[:requirement]).to eq(:unfixable)
        end
      end

      context "with range using <= upper bound" do
        let(:requirements) do
          [{ requirement: ">=1.0,<=2.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps satisfied lower bound and updates unsatisfied <= upper bound" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.0,<=2.3.4")
        end
      end

      context "with complex multi-part range" do
        let(:requirements) do
          [{ requirement: ">=1.0,<2.0,!=1.5", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "keeps satisfied constraints and updates unsatisfied upper bound" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.0,<3.0.0,!=1.5")
        end
      end
    end

    context "with WidenRanges strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

      context "with wildcard requirement" do
        let(:requirements) do
          [{ requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "converts to range" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.21,<3.0")
        end
      end

      context "with exact requirement" do
        let(:requirements) do
          [{ requirement: "=1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "converts to range" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.26,<3.0")
        end
      end

      context "with pip exact requirement" do
        let(:requirements) do
          [{ requirement: "==1.26", groups: ["pip"], source: nil, file: "environment.yml" }]
        end

        it "converts to range" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.26,<3.0")
        end
      end

      context "with existing range requirement" do
        let(:requirements) do
          [{ requirement: ">=1.26,<2.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "updates upper bound" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.26,<3.0")
        end
      end

      context "with >= requirement without upper bound" do
        let(:requirements) do
          [{ requirement: ">=1.26", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "adds upper bound" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.26,<3.0")
        end
      end

      context "with compatible release requirement" do
        let(:requirements) do
          [{ requirement: "~=1.3.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "converts to range" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.3,<3.0")
        end
      end

      context "when requirement version is too high" do
        let(:requirements) do
          [{ requirement: ">=5.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "returns unfixable" do
          expect(updater.updated_requirements.first[:requirement]).to eq(:unfixable)
        end
      end

      context "with range having different precision" do
        let(:requirements) do
          [{ requirement: ">=1.9.2,<2.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end
        let(:latest_version) { "2.10" }

        it "updates upper bound preserving structure" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.9.2,<3.0")
        end
      end
    end

    context "with BumpVersionsIfNecessary strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

      context "when requirement already satisfied" do
        let(:requirements) do
          [{ requirement: ">=2.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=2.0")
        end
      end

      context "when requirement not satisfied" do
        let(:requirements) do
          [{ requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "bumps to new version" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=2.3.*")
        end
      end

      context "when range requirement already satisfied" do
        let(:requirements) do
          [{ requirement: ">=1.0,<5.0", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq(">=1.0,<5.0")
        end
      end
    end

    context "with LockfileOnly strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      context "with any requirement" do
        let(:requirements) do
          [{ requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=1.21.*")
        end
      end
    end

    context "with no latest version" do
      let(:latest_version) { nil }
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "with any requirement" do
        let(:requirements) do
          [{ requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq("=1.21.*")
        end
      end
    end

    context "with no requirement specified" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "with nil requirement" do
        let(:requirements) do
          [{ requirement: nil, groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to be_nil
        end
      end

      context "with asterisk-only requirement" do
        let(:requirements) do
          [{ requirement: "*", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq("*")
        end
      end

      context "with empty string requirement" do
        let(:requirements) do
          [{ requirement: "", groups: ["dependencies"], source: nil, file: "environment.yml" }]
        end

        it "does not change requirement" do
          expect(updater.updated_requirements.first[:requirement]).to eq("")
        end
      end
    end

    context "with multiple requirements" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      let(:requirements) do
        [
          { requirement: "=1.21.*", groups: ["dependencies"], source: nil, file: "environment.yml" },
          { requirement: "==1.21.*", groups: ["pip"], source: nil, file: "environment.yml" }
        ]
      end

      it "updates all requirements" do
        updated = updater.updated_requirements
        expect(updated[0][:requirement]).to eq("=2.3.*")
        expect(updated[1][:requirement]).to eq("==2.3.*")
      end
    end
  end
end
