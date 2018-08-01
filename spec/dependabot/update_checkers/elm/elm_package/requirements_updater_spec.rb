# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/elm/elm_package/requirements_updater"

the_class = Dependabot::UpdateCheckers::Elm::ElmPackage::RequirementsUpdater
RSpec.describe the_class do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [elm_package_req] }
  let(:updated_source) { nil }
  let(:elm_package_req) do
    {
      file: "elm-package.json",
      requirement: requirement_string,
      groups: [],
      source: nil
    }
  end
  let(:requirement_string) { "1.4.0 <= v < 1.4.0" }

  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:requirement_string) { "1.4.0 <= v <= 1.4.0" }
    let(:latest_resolvable_version) { "1.4.0" }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(requirement_string) }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { "1.5.0" }

      context "with exact requirement" do
        let(:requirement_string) { "1.2.3 <= v <= 1.2.3" }
        its([:requirement]) { is_expected.to eq("1.5.0 <= v <= 1.5.0") }
      end

      context "with range requirement" do
        let(:requirement_string) { "1.0.0 <= v < 1.4.0" }
        its([:requirement]) { is_expected.to eq("1.5.0 <= v <= 1.5.0") }
      end
    end
  end
end
