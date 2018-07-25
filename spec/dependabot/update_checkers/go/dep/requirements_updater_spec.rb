# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/go/dep/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Go::Dep::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      updated_source: updated_source,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [manifest_req] }
  let(:updated_source) { nil }
  let(:manifest_req) do
    {
      file: "Gopkg.toml",
      requirement: manifest_req_string,
      groups: [],
      source: nil
    }
  end
  let(:manifest_req_string) { "^1.4.0" }

  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }
  let(:version_class) { Dependabot::Utils::Go::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:manifest_req_string) { "^1.0.0" }
    let(:latest_resolvable_version) { nil }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(manifest_req_string) }
    end

    context "with a git dependency" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }
      let(:manifest_req) do
        {
          file: "Gopkg.toml",
          requirement: manifest_req_string,
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
        let(:manifest_req_string) { nil }

        it "updates the source" do
          expect(updater.updated_requirements).
            to eq(
              [{
                file: "Gopkg.toml",
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

        context "updating to use releases" do
          let(:updated_source) do
            {
              type: "default",
              source: "golang.org/x/text"
            }
          end

          it "updates the source and requirement" do
            expect(updater.updated_requirements).
              to eq(
                [{
                  file: "Gopkg.toml",
                  requirement: "^1.5.0",
                  groups: [],
                  source: {
                    type: "default",
                    source: "golang.org/x/text"
                  }
                }]
              )
          end
        end
      end
    end

    context "for a library-style update" do
      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:manifest_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.2.3") }

          context "that needs to be updated" do
            let(:manifest_req_string) { "0.1.3" }
            its([:requirement]) { is_expected.to eq(">= 0.1.3, < 2.0.0") }
          end
        end

        context "and v-prefix was previously used" do
          let(:manifest_req_string) { "v1.2.3" }
          its([:requirement]) { is_expected.to eq("v1.2.3") }

          context "that needs to be updated" do
            let(:manifest_req_string) { "v0.1.3" }
            its([:requirement]) { is_expected.to eq(">= 0.1.3, < 2.0.0") }
          end
        end

        context "and a partial version was previously specified" do
          let(:manifest_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq(">= 0.1, < 2.0") }
        end

        context "and only the major part was previously specified" do
          let(:manifest_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq(">= 1, < 5") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:manifest_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.1.0.1") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:manifest_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq(">= 1.1.0.1, < 5.0.0.0") }
        end

        context "with a < condition" do
          let(:manifest_req_string) { "< 1.2.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "and a - was previously specified" do
          let(:manifest_req_string) { "1.2.3 - 1.4.0" }
          its([:requirement]) { is_expected.to eq("1.2.3 - 1.6.0") }

          context "with a pre-release version" do
            let(:manifest_req_string) { "1.2.3-rc1 - 1.4.0" }
            its([:requirement]) { is_expected.to eq("1.2.3-rc1 - 1.6.0") }
          end
        end

        context "and a pre-release was previously specified" do
          let(:manifest_req_string) { "1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("1.2.3-rc1") }

          context "when the version needs updating" do
            let(:latest_resolvable_version) { Gem::Version.new("2.5.0") }
            its([:requirement]) { is_expected.to eq(">= 1.2.3-rc1, < 3.0.0") }
          end
        end

        context "and a caret was previously specified" do
          context "that the latest version satisfies" do
            let(:manifest_req_string) { "^1.2.3" }
            its([:requirement]) { is_expected.to eq("^1.2.3") }
          end

          context "that the latest version does not satisfy" do
            let(:manifest_req_string) { "^0.8.0" }
            its([:requirement]) { is_expected.to eq(">= 0.8.0, < 2.0.0") }
          end

          context "including a pre-release" do
            let(:manifest_req_string) { "^1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("^1.2.3-rc1") }
          end

          context "updating to a pre-release of a new major version" do
            let(:manifest_req_string) { "^1.0.0-beta1" }
            let(:latest_resolvable_version) { version_class.new("2.0.0-alpha") }
            its([:requirement]) do
              is_expected.to eq(">= 1.0.0-beta1, < 3.0.0")
            end
          end

          context "including an x" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:manifest_req_string) { "^0.0.x" }
            its([:requirement]) { is_expected.to eq("^0.0.x") }

            context "when the range isn't covered" do
              let(:latest_resolvable_version) { Gem::Version.new("1.2.0") }
              its([:requirement]) { is_expected.to eq(">= 0.0.0, < 2.0.0") }
            end
          end

          context "on a version that is all zeros" do
            let(:latest_resolvable_version) { Gem::Version.new("0.0.2") }
            let(:manifest_req_string) { "^0.0.0" }
            its([:requirement]) { is_expected.to eq("^0.0.0") }
          end
        end

        context "and an x.x was previously specified" do
          let(:manifest_req_string) { "0.x.x" }
          its([:requirement]) { is_expected.to eq(">= 0.0.0, < 2.0.0") }

          context "four places" do
            let(:manifest_req_string) { "0.x.x-rc1" }
            its([:requirement]) { is_expected.to eq(">= 0.0.0-a, < 2.0.0") }
          end
        end

        context "with just *" do
          let(:manifest_req_string) { "*" }
          its([:requirement]) { is_expected.to eq("*") }
        end

        context "and a tilda was previously specified" do
          let(:latest_resolvable_version) { Gem::Version.new("2.5.3") }

          context "that the latest version satisfies" do
            let(:manifest_req_string) { "~2.5.1" }
            its([:requirement]) { is_expected.to eq("~2.5.1") }
          end

          context "that the latest version does not satisfy" do
            let(:manifest_req_string) { "~2.4.1" }
            its([:requirement]) { is_expected.to eq(">= 2.4.1, < 2.6.0") }
          end

          context "including a pre-release" do
            let(:manifest_req_string) { "~2.5.1-rc1" }
            its([:requirement]) { is_expected.to eq("~2.5.1-rc1") }
          end

          context "including an x" do
            let(:manifest_req_string) { "~2.x.x" }
            its([:requirement]) { is_expected.to eq("~2.x.x") }

            context "when the range isn't covered" do
              let(:manifest_req_string) { "~2.4.x" }
              its([:requirement]) { is_expected.to eq(">= 2.4.0, < 2.6.0") }
            end
          end
        end

        context "and there were multiple specifications" do
          let(:manifest_req_string) { "> 1.0.0, < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, < 1.6.0") }

          context "already valid" do
            let(:manifest_req_string) { "> 1.0.0, < 1.7.0" }
            its([:requirement]) { is_expected.to eq(manifest_req_string) }
          end

          context "specified with || and valid" do
            let(:manifest_req_string) { "^1.0.0 || ^2.0.0" }
            its([:requirement]) { is_expected.to eq(manifest_req_string) }
          end

          context "that include a pre-release" do
            let(:manifest_req_string) { ">=1.2.0, <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0, <1.6.0") }
          end
        end

        context "and there were multiple requirements" do
          let(:requirements) { [manifest_req, other_manifest_req] }

          let(:other_manifest_req) do
            {
              file: "another/Gopkg.toml",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:manifest_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.x.x" }

          it "updates the requirement that needs to be updated" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "Gopkg.toml",
                  requirement: "^1.2.3",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/Gopkg.toml",
                  requirement: ">= 0.0.0, < 2.0.0",
                  groups: [],
                  source: nil
                }
              ]
            )
          end

          context "for the same file" do
            let(:requirements) do
              [
                {
                  requirement: "0.1.x",
                  file: "Gopkg.toml",
                  groups: ["dependencies"],
                  source: nil
                },
                {
                  requirement: "^0.1.0",
                  file: "Gopkg.toml",
                  groups: ["devDependencies"],
                  source: nil
                }
              ]
            end

            it "updates both requirements" do
              expect(updater.updated_requirements).to match_array(
                [
                  {
                    requirement: ">= 0.1.0, < 2.0.0",
                    file: "Gopkg.toml",
                    groups: ["dependencies"],
                    source: nil
                  },
                  {
                    requirement: ">= 0.1.0, < 2.0.0",
                    file: "Gopkg.toml",
                    groups: ["devDependencies"],
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
end
