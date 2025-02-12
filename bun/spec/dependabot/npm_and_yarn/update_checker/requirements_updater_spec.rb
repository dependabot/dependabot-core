# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/npm_and_yarn/update_checker/requirements_updater"
require "dependabot/requirements_update_strategy"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      updated_source: updated_source,
      update_strategy: update_strategy,
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

  let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
  let(:latest_resolvable_version) { "1.5.0" }
  let(:version_class) { Dependabot::NpmAndYarn::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    let(:latest_resolvable_version) { nil }
    let(:package_json_req_string) { "^1.0.0" }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }

      its([:requirement]) { is_expected.to eq(package_json_req_string) }
    end

    context "with a dist tag" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
      let(:package_json_req_string) { "latest" }

      its([:requirement]) { is_expected.to eq(package_json_req_string) }

      context "when it starts with a v" do
        let(:package_json_req_string) { "very-latest" }

        its([:requirement]) { is_expected.to eq(package_json_req_string) }
      end
    end

    context "with a git dependency" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
      let(:package_json_req) do
        {
          file: "package.json",
          requirement: package_json_req_string,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/jonschlinkert/is-number",
            branch: nil,
            ref: "2.0.0"
          }
        }
      end
      let(:updated_source) do
        {
          type: "git",
          url: "https://github.com/jonschlinkert/is-number",
          branch: nil,
          ref: "2.1.0"
        }
      end

      context "with no requirement" do
        let(:package_json_req_string) { nil }

        it "updates the source" do
          expect(updater.updated_requirements)
            .to eq(
              [{
                file: "package.json",
                requirement: nil,
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "2.1.0"
                }
              }]
            )
        end

        context "when updating to use npm" do
          let(:updated_source) { nil }

          it "updates the source and requirement" do
            expect(updater.updated_requirements)
              .to eq(
                [{
                  file: "package.json",
                  requirement: "^1.5.0",
                  groups: [],
                  source: nil
                }]
              )
          end
        end
      end

      context "with a requirement" do
        let(:package_json_req_string) { "~0.9.0" }

        it "updates the source" do
          expect(updater.updated_requirements)
            .to eq(
              [{
                file: "package.json",
                requirement: "~1.5.0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/jonschlinkert/is-number",
                  branch: nil,
                  ref: "2.1.0"
                }
              }]
            )
        end

        context "when updating to use npm" do
          let(:updated_source) { nil }

          it "updates the source and requirement" do
            expect(updater.updated_requirements)
              .to eq(
                [{
                  file: "package.json",
                  requirement: "~1.5.0",
                  groups: [],
                  source: nil
                }]
              )
          end
        end
      end
    end

    context "when dealing with a requirement having its version bumped" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "when a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when v-prefix was previously used" do
          let(:package_json_req_string) { "v1.2.3" }

          its([:requirement]) { is_expected.to eq("v1.5.0") }

          context "when requirement is capitalised (and therefore invalid)" do
            let(:package_json_req_string) { "V1.2.3" }

            its([:requirement]) { is_expected.to eq("V1.2.3") }
          end
        end

        context "when a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }

          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "when only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }

          its([:requirement]) { is_expected.to eq("4") }
        end

        context "when the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }

          its([:requirement]) { is_expected.to eq("4") }
        end

        context "when a caret was previously specified" do
          let(:package_json_req_string) { "^1.2.3" }

          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "when v-prefix was previously used" do
            let(:package_json_req_string) { "^v1.2.3" }

            its([:requirement]) { is_expected.to eq("^v1.5.0") }
          end

          context "with a || separator" do
            let(:package_json_req_string) { "^0.5.1 || ^1.2.3" }

            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end
        end

        context "when a pre-release was previously specified" do
          let(:package_json_req_string) { "^1.2.3-rc1" }

          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "when needing an update" do
            let(:package_json_req_string) { "1.2.3-rc1" }

            its([:requirement]) { is_expected.to eq("1.5.0") }

            context "when the version is new pre-release version" do
              let(:latest_resolvable_version) do
                Dependabot::NpmAndYarn::Version.new("1.2.3-beta.2")
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

        context "when there were multiple range specifications" do
          let(:package_json_req_string) { "> 1.0.0 < 1.2.0" }

          its([:requirement]) { is_expected.to eq("> 1.0.0 < 1.6.0") }

          context "when requirement is already valid" do
            let(:package_json_req_string) { "> 1.0.0 < 1.7.0" }

            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "when including a pre-release" do
            let(:package_json_req_string) { ">=1.2.0 <1.4.0-dev" }

            its([:requirement]) { is_expected.to eq(">=1.2.0 <1.6.0") }
          end
        end

        context "when an x.x was previously specified" do
          let(:package_json_req_string) { "^0.x.x" }

          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "when an x.x was previously specified with four places" do
          let(:package_json_req_string) { "^0.x.x.rc1" }

          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "when there were multiple requirements" do
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
            expect(updater.updated_requirements).to contain_exactly({
              file: "package.json",
              requirement: "^1.5.0",
              groups: [],
              source: nil
            }, {
              file: "another/package.json",
              requirement: "^1.x.x",
              groups: [],
              source: nil
            })
          end

          context "when one of them is a pre-release" do
            let(:package_json_req_string) { "0.4.5" }
            let(:other_requirement_string) { "1.1.0-alpha.1" }

            context "when the version is new pre-release version" do
              let(:latest_resolvable_version) do
                Dependabot::NpmAndYarn::Version.new("1.1.0-alpha.1")
              end

              it "updates the non-prerelease requirement" do
                expect(updater.updated_requirements).to contain_exactly({
                  file: "package.json",
                  requirement: "1.1.0-alpha.1",
                  groups: [],
                  source: nil
                }, {
                  file: "another/package.json",
                  requirement: "1.1.0-alpha.1",
                  groups: [],
                  source: nil
                })
              end
            end
          end
        end
      end
    end

    context "when dealing with a requirement having its version bumped if required" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "when a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when v-prefix was previously used" do
          let(:package_json_req_string) { "v1.2.3" }

          its([:requirement]) { is_expected.to eq("v1.5.0") }

          context "when requirement is capitalised (and therefore invalid)" do
            let(:package_json_req_string) { "V1.2.3" }

            its([:requirement]) { is_expected.to eq("V1.2.3") }
          end
        end

        context "when a caret was previously specified" do
          let(:package_json_req_string) { "^1.2.3" }

          its([:requirement]) { is_expected.to eq("^1.2.3") }

          context "when this version doesn't satisfy" do
            let(:package_json_req_string) { "^v0.2.3" }

            its([:requirement]) { is_expected.to eq("^v1.5.0") }
          end

          context "with a || separator" do
            let(:package_json_req_string) { "^0.5.1 || ^1.2.3" }

            its([:requirement]) { is_expected.to eq(package_json_req_string) }

            context "when this version doesn't satisfy" do
              let(:latest_resolvable_version) { "2.1.0" }

              its([:requirement]) { is_expected.to eq("^2.1.0") }
            end
          end
        end
      end
    end

    context "when dealing with a requirement being widened" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "when a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when v-prefix was previously used" do
          let(:package_json_req_string) { "v1.2.3" }

          its([:requirement]) { is_expected.to eq("v1.5.0") }
        end

        context "when a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }

          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "when only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }

          its([:requirement]) { is_expected.to eq("4") }
        end

        context "when the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }

          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with a < condition" do
          let(:package_json_req_string) { "< 1.2.0" }

          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "when a - was previously specified" do
          let(:package_json_req_string) { "1.2.3 - 1.4.0" }

          its([:requirement]) { is_expected.to eq("1.2.3 - 1.6.0") }

          context "with a pre-release version" do
            let(:package_json_req_string) { "1.2.3-rc1 - 1.4.0" }

            its([:requirement]) { is_expected.to eq("1.2.3-rc1 - 1.6.0") }
          end
        end

        context "when a pre-release was previously specified" do
          let(:package_json_req_string) { "1.2.3-rc1" }

          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "when a caret was previously specified" do
          context "when the latest version satisfies" do
            let(:package_json_req_string) { "^1.2.3" }

            its([:requirement]) { is_expected.to eq("^1.2.3") }
          end

          context "when the latest version does not satisfy" do
            let(:package_json_req_string) { "^0.8.0" }

            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end

          context "when including a pre-release" do
            let(:package_json_req_string) { "^1.2.3-rc1" }

            its([:requirement]) { is_expected.to eq("^1.2.3-rc1") }
          end

          context "when updating to a pre-release of a new major version" do
            let(:package_json_req_string) { "^1.0.0-beta1" }
            let(:latest_resolvable_version) { version_class.new("2.0.0-alpha") }

            its([:requirement]) { is_expected.to eq("^2.0.0-alpha") }
          end

          context "when including an x" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:package_json_req_string) { "^0.0.x" }

            its([:requirement]) { is_expected.to eq("^0.0.x") }

            context "when the range isn't covered" do
              let(:latest_resolvable_version) { Gem::Version.new("0.2.0") }

              its([:requirement]) { is_expected.to eq("^0.2.x") }
            end
          end

          context "when dealing with a version that is all zeros" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:package_json_req_string) { "^0.0.0" }

            its([:requirement]) { is_expected.to eq("^0.0.2") }
          end
        end

        context "when an x.x was previously specified" do
          let(:package_json_req_string) { "0.x.x" }

          its([:requirement]) { is_expected.to eq("1.x.x") }

          context "when dealing with four places" do
            let(:package_json_req_string) { "0.x.x.rc1" }

            its([:requirement]) { is_expected.to eq("1.x.x") }
          end
        end

        context "with just *" do
          let(:package_json_req_string) { "*" }

          its([:requirement]) { is_expected.to eq("*") }
        end

        context "when a ~> was previously specified" do
          let(:latest_resolvable_version) { Gem::Version.new("2.5.3") }

          context "when the latest version satisfies" do
            let(:package_json_req_string) { "~>2.5.1" }

            its([:requirement]) { is_expected.to eq("~>2.5.1") }
          end

          context "when the latest version does not satisfy" do
            let(:package_json_req_string) { "~>2.4.1" }

            its([:requirement]) { is_expected.to eq("~>2.5.3") }
          end
        end

        context "when a tilde was previously specified" do
          let(:latest_resolvable_version) { Gem::Version.new("2.5.3") }

          context "when the latest version satisfies" do
            let(:package_json_req_string) { "~2.5.1" }

            its([:requirement]) { is_expected.to eq("~2.5.1") }
          end

          context "when the latest version does not satisfy" do
            let(:package_json_req_string) { "~2.4.1" }

            its([:requirement]) { is_expected.to eq("~2.5.3") }
          end

          context "when including a pre-release" do
            let(:package_json_req_string) { "~2.5.1-rc1" }

            its([:requirement]) { is_expected.to eq("~2.5.1-rc1") }
          end

          context "when including an x" do
            let(:package_json_req_string) { "~2.x.x" }

            its([:requirement]) { is_expected.to eq("~2.x.x") }

            context "when the range isn't covered" do
              let(:package_json_req_string) { "~2.4.x" }

              its([:requirement]) { is_expected.to eq("~2.5.x") }
            end
          end
        end

        context "when there were multiple specifications" do
          let(:package_json_req_string) { "> 1.0.0 < 1.2.0" }

          its([:requirement]) { is_expected.to eq("> 1.0.0 < 1.6.0") }

          context "when requirement is already valid" do
            let(:package_json_req_string) { "> 1.0.0 < 1.7.0" }

            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "when specified with || and valid" do
            let(:package_json_req_string) { "^1.0.0 || ^2.0.0" }

            its([:requirement]) { is_expected.to eq(package_json_req_string) }
          end

          context "when including a pre-release" do
            let(:package_json_req_string) { ">=1.2.0 <1.4.0-dev" }

            its([:requirement]) { is_expected.to eq(">=1.2.0 <1.6.0") }
          end
        end

        context "when there were multiple requirements" do
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
            expect(updater.updated_requirements).to contain_exactly({
              file: "package.json",
              requirement: "^1.2.3",
              groups: [],
              source: nil
            }, {
              file: "another/package.json",
              requirement: "^1.x.x",
              groups: [],
              source: nil
            })
          end

          context "when dealing with the same file" do
            let(:requirements) do
              [{
                requirement: "0.1.x",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "^0.1.0",
                file: "package.json",
                groups: ["devDependencies"],
                source: nil
              }]
            end

            it "updates both requirements" do
              expect(updater.updated_requirements).to contain_exactly({
                requirement: "1.5.x",
                file: "package.json",
                groups: ["dependencies"],
                source: nil
              }, {
                requirement: "^1.5.0",
                file: "package.json",
                groups: ["devDependencies"],
                source: nil
              })
            end
          end
        end
      end
    end

    context "when dealing with a requirement being left alone" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it "does not update any requirements" do
        expect(updater.updated_requirements).to eq(requirements)
      end
    end
  end
end
