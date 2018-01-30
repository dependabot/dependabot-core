# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/php/composer/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Php::Composer::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      library: library,
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

  let(:library) { false }
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

    context "for an app requirement" do
      let(:library) { false }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

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

        context "and a stability flag was specified" do
          let(:composer_json_req_string) { "1.2.3@dev" }
          its([:requirement]) { is_expected.to eq("1.5.0@dev") }
        end

        context "and an alias was specified" do
          let(:composer_json_req_string) { "mybranch as 1.2.x" }
          its([:requirement]) { is_expected.to eq(composer_json_req_string) }

          context "that specifies a numeric version" do
            let(:composer_json_req_string) { "1.2.0 as 1.0.0" }
            its([:requirement]) { is_expected.to eq("1.5.0 as 1.0.0") }
          end
        end

        context "and a partial version was previously specified" do
          let(:composer_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and only the major part was previously specified" do
          let(:composer_json_req_string) { "1" }
          let(:latest_resolvable_version) { "4.5.0" }
          its([:requirement]) { is_expected.to eq("4.5.0") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { "4" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          let(:composer_json_req_string) { "^0.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "specified at two digits" do
            let(:composer_json_req_string) { "^0.2" }
            its([:requirement]) { is_expected.to eq("^1.5") }
          end

          context "with a stability flag" do
            let(:composer_json_req_string) { "^0.2.3@dev" }
            its([:requirement]) { is_expected.to eq("^1.5.0@dev") }
          end
        end

        context "and a >= was previously specified" do
          let(:composer_json_req_string) { ">= 1.2.3" }
          its([:requirement]) { is_expected.to eq(">= 1.2.3") }
        end

        context "and a tilda was previously specified" do
          let(:latest_resolvable_version) { "2.5.3" }

          context "with three digits" do
            let(:composer_json_req_string) { "~1.5.1" }
            its([:requirement]) { is_expected.to eq("~2.5.3") }
          end

          context "with two digits" do
            let(:composer_json_req_string) { "~1.4" }
            its([:requirement]) { is_expected.to eq("~2.5") }
          end
        end

        context "and a pre-release was previously specified" do
          let(:composer_json_req_string) { "^0.2.3beta" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a * was previously specified" do
          context "and two *'s were specified" do
            let(:composer_json_req_string) { "1.4.*" }
            its([:requirement]) { is_expected.to eq("1.5.*") }
          end

          context "and two *'s were specified" do
            let(:composer_json_req_string) { "1.*.*" }
            its([:requirement]) { is_expected.to eq("1.*.*") }

            context "that aren't satisfied" do
              let(:composer_json_req_string) { "0.*.*" }
              its([:requirement]) { is_expected.to eq("1.*.*") }
            end
          end

          context "with fewer digits than the new version" do
            let(:composer_json_req_string) { "0.*" }
            its([:requirement]) { is_expected.to eq("1.*") }
          end

          context "with just *" do
            let(:composer_json_req_string) { "*" }
            its([:requirement]) { is_expected.to eq("*") }
          end
        end

        context "and a < was previously specified" do
          let(:composer_json_req_string) { "< 1.2.3" }
          its([:requirement]) { is_expected.to eq("< 1.5.1") }
        end

        context "and a - was previously specified" do
          let(:composer_json_req_string) { "1.2.3 - 1.4.0" }
          its([:requirement]) { is_expected.to eq("1.2.3 - 1.6.0") }

          context "with a pre-release version" do
            let(:composer_json_req_string) { "1.2.3-rc1 - 1.4.0" }
            its([:requirement]) { is_expected.to eq("1.2.3-rc1 - 1.6.0") }
          end
        end

        context "and there were multiple specifications" do
          let(:composer_json_req_string) { "> 1.0.0 < 1.2.0" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "specified with commas" do
            let(:composer_json_req_string) { "> 1.0.0, < 1.2.0" }
            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end

          context "specified with ||" do
            let(:composer_json_req_string) { "^0.0.0 || ^2.0.0" }
            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end

          context "that include a pre-release" do
            let(:composer_json_req_string) { ">=1.2.0,<1.4.0-dev" }
            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end
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
          let(:composer_json_req_string) { "1.2.3" }
          let(:other_requirement_string) { "0.*.*" }

          it "updates both requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "composer.json",
                  requirement: "1.5.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/composer.json",
                  requirement: "1.*.*",
                  groups: [],
                  source: nil
                }
              ]
            )
          end
        end
      end
    end

    context "for a library requirement" do
      let(:library) { true }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously specified" do
          let(:composer_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:composer_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "with a stability flag" do
          let(:composer_json_req_string) { "1.2.3@dev" }
          its([:requirement]) { is_expected.to eq("1.5.0@dev") }
        end

        context "with a pre-release" do
          let(:latest_resolvable_version) { "1.0-beta2" }
          let(:composer_json_req_string) { "1.0-beta1" }
          its([:requirement]) { is_expected.to eq("1.0-beta2") }
        end

        context "and only the major part was previously specified" do
          let(:composer_json_req_string) { "1" }
          let(:latest_resolvable_version) { "4.5.0" }
          its([:requirement]) { is_expected.to eq("4.5.0") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:composer_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { "4" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          context "that the latest version satisfies" do
            let(:composer_json_req_string) { "^1.2.3" }
            its([:requirement]) { is_expected.to eq("^1.2.3") }
          end

          context "with two digits" do
            let(:composer_json_req_string) { "^1.2" }
            its([:requirement]) { is_expected.to eq("^1.2") }
          end

          context "that the latest version does not satisfy" do
            let(:composer_json_req_string) { "^0.8.0" }
            its([:requirement]) { is_expected.to eq("^0.8.0|^1.0.0") }

            context "with two digits" do
              let(:composer_json_req_string) { "^0.8" }
              its([:requirement]) { is_expected.to eq("^0.8|^1.0") }
            end
          end

          context "including a pre-release" do
            let(:composer_json_req_string) { "^1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("^1.2.3-rc1") }
          end

          context "on a version that is all zeros" do
            let(:latest_resolvable_version) { "0.0.2" }
            let(:composer_json_req_string) { "^0.0.0" }
            its([:requirement]) { is_expected.to eq("^0.0.0|^0.0.2") }
          end
        end

        context "and a >= was previously specified" do
          let(:composer_json_req_string) { ">= 1.2.3" }
          its([:requirement]) { is_expected.to eq(">= 1.2.3") }
        end

        context "and a < was previously specified" do
          let(:composer_json_req_string) { "< 1.2.3" }
          its([:requirement]) { is_expected.to eq("< 1.5.1") }
        end

        context "and a - was previously specified" do
          let(:composer_json_req_string) { "1.2.3 - 1.4.0" }
          its([:requirement]) { is_expected.to eq("1.2.3 - 1.6.0") }
        end

        context "and a *.* was previously specified" do
          let(:composer_json_req_string) { "0.*.*" }
          its([:requirement]) { is_expected.to eq("0.*.*|1.*.*") }

          context "with fewer digits than the new version" do
            let(:composer_json_req_string) { "0.*" }
            its([:requirement]) { is_expected.to eq("0.*|1.*") }
          end

          context "with just *" do
            let(:composer_json_req_string) { "*" }
            its([:requirement]) { is_expected.to eq("*") }
          end
        end

        context "and a tilda was previously specified" do
          let(:latest_resolvable_version) { "2.5.3" }

          context "that the latest version satisfies" do
            let(:composer_json_req_string) { "~2.5.1" }
            its([:requirement]) { is_expected.to eq("~2.5.1") }
          end

          context "with a v prefix" do
            let(:composer_json_req_string) { "~v2.5.1" }
            its([:requirement]) { is_expected.to eq("~v2.5.1") }
          end

          context "with two digits" do
            let(:composer_json_req_string) { "~2.4" }
            its([:requirement]) { is_expected.to eq("~2.4") }
          end

          context "that the latest version does not satisfy" do
            let(:composer_json_req_string) { "~2.4.1" }
            its([:requirement]) { is_expected.to eq("~2.4.1|~2.5.0") }
          end

          context "including a pre-release" do
            let(:composer_json_req_string) { "~2.5.1-rc1" }
            its([:requirement]) { is_expected.to eq("~2.5.1-rc1") }
          end
        end

        context "and there were multiple specifications" do
          let(:composer_json_req_string) { "> 1.0.0 < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0 < 1.6.0") }

          context "specified with commas" do
            let(:composer_json_req_string) { "> 1.0.0, < 1.2.0" }
            its([:requirement]) { is_expected.to eq("> 1.0.0, < 1.6.0") }
          end

          context "specified with commas and valid" do
            let(:composer_json_req_string) { "> 1.0.0, < 1.7.0" }
            its([:requirement]) { is_expected.to eq(composer_json_req_string) }
          end

          context "that include a pre-release" do
            let(:composer_json_req_string) { ">=1.2.0,<1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0,<1.6.0") }
          end

          context "specified with ||" do
            let(:composer_json_req_string) { "^1.0.0 || ^2.0.0" }
            its([:requirement]) { is_expected.to eq(composer_json_req_string) }
          end

          context "specified with || and commas and invalid" do
            let(:composer_json_req_string) { "> 1.0, < 1.2 || ^2.0.0" }
            its([:requirement]) do
              is_expected.to eq("> 1.0, < 1.2 || ^2.0.0|^1.0.0")
            end
          end

          context "specified with || and commas and valid" do
            let(:composer_json_req_string) { "> 1.0, < 1.6 || ^2.0.0" }
            its([:requirement]) { is_expected.to eq(composer_json_req_string) }
          end

          context "specified with |" do
            let(:latest_resolvable_version) { "2.5.3" }
            let(:composer_json_req_string) { "~0.4|~1.0" }
            its([:requirement]) { is_expected.to eq("~0.4|~1.0|~2.0") }
          end
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
          let(:other_requirement_string) { "0.*.*" }

          it "updates the requirement that needs to be updated" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "composer.json",
                  requirement: "^1.2.3",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/composer.json",
                  requirement: "0.*.*|1.*.*",
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
