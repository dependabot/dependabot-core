# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java_script/npm_and_yarn/"\
        "requirements_updater"

module_to_test = Dependabot::UpdateCheckers::JavaScript
RSpec.describe module_to_test::NpmAndYarn::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      updated_source: updated_source,
      library: library,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [package_json_req] }
  let(:updated_source) { nil }
  let(:package_json_req) do
    {
      file: "package.json",
      requirement: package_json_req_string,
      groups: [],
      source: nil
    }
  end
  let(:package_json_req_string) { "^1.4.0" }

  let(:library) { false }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:package_json_req_string) { "^1.0.0" }
    let(:latest_resolvable_version) { nil }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(package_json_req_string) }
    end

    context "with a dist tag" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
      let(:package_json_req_string) { "latest" }
      its([:requirement]) { is_expected.to eq(package_json_req_string) }
    end

    context "with a git dependency with no requirement" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
      let(:package_json_req) do
        {
          file: "package.json",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: "2.0.0"
          }
        }
      end

      it { is_expected.to eq(package_json_req) }
    end

    context "for an app requirement" do
      let(:library) { false }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          let(:package_json_req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:package_json_req_string) { "^1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "that needs updating" do
            let(:package_json_req_string) { "1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("1.5.0") }

            context "to a new pre-release version" do
              let(:latest_resolvable_version) do
                module_to_test::NpmAndYarn::Version.new("1.2.3-beta.2")
              end
              let(:package_json_req_string) { "1.2.3-beta" }
              its([:requirement]) { is_expected.to eq("1.2.3-beta.2") }
            end
          end
        end

        context "with just *" do
          let(:package_json_req_string) { "*" }
          its([:requirement]) { is_expected.to eq("*") }
        end

        context "with a < condition" do
          let(:package_json_req_string) { "< 1.2.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "and there were multiple range specifications" do
          let(:package_json_req_string) { "> 1.0.0 < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0 < 1.6.0") }

          context "already valid" do
            let(:package_json_req_string) { "> 1.0.0 < 1.7.0" }
            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "that include a pre-release" do
            let(:package_json_req_string) { ">=1.2.0 <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0 <1.6.0") }
          end
        end

        context "and an x.x was previously specified" do
          let(:package_json_req_string) { "^0.x.x" }
          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "and an x.x was previously specified with four places" do
          let(:package_json_req_string) { "^0.x.x.rc1" }
          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "and there were multiple requirements" do
          let(:requirements) { [package_json_req, other_package_json_req] }

          let(:other_package_json_req) do
            {
              file: "another/package.json",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:package_json_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.x.x" }

          it "updates both requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "package.json",
                  requirement: "^1.5.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/package.json",
                  requirement: "^1.x.x",
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
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with a < condition" do
          let(:package_json_req_string) { "< 1.2.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "and a - was previously specified" do
          let(:package_json_req_string) { "1.2.3 - 1.4.0" }
          its([:requirement]) { is_expected.to eq("1.2.3 - 1.6.0") }

          context "with a pre-release version" do
            let(:package_json_req_string) { "1.2.3-rc1 - 1.4.0" }
            its([:requirement]) { is_expected.to eq("1.2.3-rc1 - 1.6.0") }
          end
        end

        context "and a pre-release was previously specified" do
          let(:package_json_req_string) { "1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a caret was previously specified" do
          context "that the latest version satisfies" do
            let(:package_json_req_string) { "^1.2.3" }
            its([:requirement]) { is_expected.to eq("^1.2.3") }
          end

          context "that the latest version does not satisfy" do
            let(:package_json_req_string) { "^0.8.0" }
            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end

          context "including a pre-release" do
            let(:package_json_req_string) { "^1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("^1.2.3-rc1") }
          end

          context "including an x" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:package_json_req_string) { "^0.0.x" }
            its([:requirement]) { is_expected.to eq("^0.0.x") }

            context "when the range isn't covered" do
              let(:latest_resolvable_version) { Gem::Version.new("0.2.0") }
              its([:requirement]) { is_expected.to eq("^0.2.x") }
            end
          end

          context "on a version that is all zeros" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:package_json_req_string) { "^0.0.0" }
            its([:requirement]) { is_expected.to eq("^0.0.2") }
          end
        end

        context "and an x.x was previously specified" do
          let(:package_json_req_string) { "0.x.x" }
          its([:requirement]) { is_expected.to eq("1.x.x") }

          context "four places" do
            let(:package_json_req_string) { "0.x.x.rc1" }
            its([:requirement]) { is_expected.to eq("1.x.x") }
          end
        end

        context "with just *" do
          let(:package_json_req_string) { "*" }
          its([:requirement]) { is_expected.to eq("*") }
        end

        context "and a tilda was previously specified" do
          let(:latest_resolvable_version) { Gem::Version.new("2.5.3") }

          context "that the latest version satisfies" do
            let(:package_json_req_string) { "~2.5.1" }
            its([:requirement]) { is_expected.to eq("~2.5.1") }
          end

          context "that the latest version does not satisfy" do
            let(:package_json_req_string) { "~2.4.1" }
            its([:requirement]) { is_expected.to eq("~2.5.3") }
          end

          context "including a pre-release" do
            let(:package_json_req_string) { "~2.5.1-rc1" }
            its([:requirement]) { is_expected.to eq("~2.5.1-rc1") }
          end

          context "including an x" do
            let(:package_json_req_string) { "~2.x.x" }
            its([:requirement]) { is_expected.to eq("~2.x.x") }

            context "when the range isn't covered" do
              let(:package_json_req_string) { "~2.4.x" }
              its([:requirement]) { is_expected.to eq("~2.5.x") }
            end
          end
        end

        context "and there were multiple specifications" do
          let(:package_json_req_string) { "> 1.0.0 < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0 < 1.6.0") }

          context "already valid" do
            let(:package_json_req_string) { "> 1.0.0 < 1.7.0" }
            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "specified with || and valid" do
            let(:package_json_req_string) { "^1.0.0 || ^2.0.0" }
            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "that include a pre-release" do
            let(:package_json_req_string) { ">=1.2.0 <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0 <1.6.0") }
          end
        end

        context "and there were multiple requirements" do
          let(:requirements) { [package_json_req, other_package_json_req] }

          let(:other_package_json_req) do
            {
              file: "another/package.json",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:package_json_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.x.x" }

          it "updates the requirement that needs to be updated" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "package.json",
                  requirement: "^1.2.3",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/package.json",
                  requirement: "^1.x.x",
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
