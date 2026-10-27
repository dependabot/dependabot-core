# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"
require "dependabot/bun/update_checker/requirements_updater"

RSpec.describe Dependabot::Bun::UpdateChecker::RequirementsUpdater do
  subject(:updated_requirement) { updater.updated_requirements.first.requirement }

  let(:updater) do
    described_class.new(
      requirements: [{ file: "package.json", requirement: requirement, groups: [], source: nil }],
      updated_source: nil,
      update_strategy: Dependabot::RequirementsUpdateStrategy::WidenRanges,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  describe "#updated_requirements when widening ranges" do
    context "when the requirement has several alternatives and the new version is covered" do
      let(:requirement) { "^1.0.0 || ^2.0.0" }
      let(:latest_resolvable_version) { "1.5.0" }

      it { is_expected.to eq("^1.0.0 || ^2.0.0") }
    end

    context "when the requirement has several alternatives and the new version is not covered" do
      let(:requirement) { "^2.13.0 || ^3.0.0 || ^4.0.0" }
      let(:latest_resolvable_version) { "6.2.1" }

      it { is_expected.to eq("^2.13.0 || ^3.0.0 || ^4.0.0 || ^6.2.1") }

      context "with tilde ranges" do
        let(:requirement) { "~1.2.0 || ~1.3.0" }
        let(:latest_resolvable_version) { "1.4.5" }

        it { is_expected.to eq("~1.2.0 || ~1.3.0 || ~1.4.5") }
      end

      context "with a space after the operator" do
        let(:requirement) { "~ 1.2.0 || ~ 1.3.0" }
        let(:latest_resolvable_version) { "1.4.5" }

        it { is_expected.to eq("~ 1.2.0 || ~ 1.3.0 || ~ 1.4.5") }
      end

      context "with exact versions" do
        let(:requirement) { "1.0.0 || 2.0.0" }
        let(:latest_resolvable_version) { "3.0.0" }

        it { is_expected.to eq("1.0.0 || 2.0.0 || 3.0.0") }
      end

      context "when the last alternative would not admit the new version" do
        let(:requirement) { "^1.0.0 || >9.0.0" }
        let(:latest_resolvable_version) { "2.0.0" }

        it { is_expected.to eq("^1.0.0 || >9.0.0 || ^2.0.0") }
      end

      context "when the last alternative is a range with several comparators" do
        let(:requirement) { "^1.0.0 || ^2.0.0 >=2.1.0" }
        let(:latest_resolvable_version) { "3.0.0" }

        it { is_expected.to eq("^1.0.0 || ^2.0.0 >=2.1.0 || ^3.0.0") }
      end

      context "with build metadata on the old and the new version" do
        let(:requirement) { "1.0.0 || 2.0.0+old" }
        let(:latest_resolvable_version) { "3.0.0+new" }

        it { is_expected.to eq("1.0.0 || 2.0.0+old || 3.0.0+new") }
      end
    end
  end
end
