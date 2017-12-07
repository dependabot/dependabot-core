# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/php/composer/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Php::Composer::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      existing_version: existing_version,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [composer_json_req] }
  let(:composer_json_req) do
    {
      file: "composer.json",
      requirement: composer_json_req_string,
      groups: [],
      source: nil
    }
  end
  let(:composer_json_req_string) { "^1.4.0" }

  let(:existing_version) { "1.0.0" }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:composer_json_req_string) { "^1.0.0" }
    let(:latest_resolvable_version) { nil }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(composer_json_req_string) }
    end

    context "with an existing version" do
      let(:existing_version) { "1.0.0" }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:composer_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a version with a v-prefix was previously specified" do
          let(:composer_json_req_string) { "v1.2.3" }
          its([:requirement]) { is_expected.to eq("v1.5.0") }
        end

        context "and a non-numeric version was previously specified" do
          let(:composer_json_req_string) { "@stable" }
          its([:requirement]) { is_expected.to eq("@stable") }
        end

        context "and a partial version was previously specified" do
          let(:composer_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:composer_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          let(:composer_json_req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:composer_json_req_string) { "^1.2.3beta" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and an *.* was previously specified" do
          let(:composer_json_req_string) { "^0.*.*" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "and there were multiple requirements" do
          let(:requirements) { [composer_json_req, other_composer_json_req] }

          let(:other_composer_json_req) do
            {
              file: "another/composer.json",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:composer_json_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.*.*" }

          it "updates both requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "composer.json",
                  requirement: "^1.5.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/composer.json",
                  requirement: "^1.*.*",
                  groups: [],
                  source: nil
                }
              ]
            )
          end
        end
      end
    end
  end
end
