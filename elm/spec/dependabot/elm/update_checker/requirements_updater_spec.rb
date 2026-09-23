# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/elm/update_checker/requirements_updater"

RSpec.describe Dependabot::Elm::UpdateChecker::RequirementsUpdater do
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

    let(:latest_resolvable_version) { "1.4.0" }
    let(:requirement_string) { "1.4.0 <= v <= 1.4.0" }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "with a malformed requirement" do
      let(:elm_package_req) do
        {
          file: "elm-package.json",
          requirement: 123,
          groups: [],
          source: nil
        }
      end

      it "raises a type error" do
        expect { updater.updated_requirements }
          .to raise_error(TypeError, "requirement must be a string, :unfixable, or nil")
      end
    end

    context "with string-keyed nested source details" do
      let(:elm_package_req) do
        {
          file: "elm-package.json",
          requirement: requirement_string,
          groups: [],
          source: { "type" => "registry", "custom" => "preserved" }
        }
      end

      it "preserves the source payload and key style" do
        source = updater.updated_requirements.first.source_hash

        expect(source).to include("type" => "registry", "custom" => "preserved")
        expect(source).not_to have_key(:type)
      end
    end

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }

      its([:requirement]) { is_expected.to eq(requirement_string) }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { "1.5.0" }

      context "with exact requirement" do
        let(:requirement_string) { "1.2.3 <= v <= 1.2.3" }

        its([:requirement]) { is_expected.to eq("1.5.0 <= v <= 1.5.0") }

        context "when specified as a single version" do
          let(:requirement_string) { "1.2.3" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end
      end

      context "with range requirement" do
        let(:requirement_string) { "1.0.0 <= v < 2.0.0" }

        context "when needing an update" do
          let(:latest_resolvable_version) { "2.0.0" }

          its([:requirement]) { is_expected.to eq("1.0.0 <= v < 3.0.0") }
        end

        context "when not needing an update" do
          its([:requirement]) { is_expected.to eq("1.0.0 <= v < 2.0.0") }
        end
      end
    end
  end
end
