# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/cargo/update_checker/requirements_updater"
require "dependabot/requirements_update_strategy"

RSpec.describe Dependabot::Cargo::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      update_strategy: update_strategy,
      updated_source: updated_source,
      target_version: target_version
    )
  end

  let(:updated_source) { nil }
  let(:requirements) do
    [{
      file: "Cargo.toml",
      requirement: req_string,
      groups: [],
      source: nil
    }]
  end
  let(:req_string) { "^1.4.0" }

  let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
  let(:target_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:req_string) { "^1.0.0" }

    context "when there is no latest version" do
      let(:target_version) { nil }
      its([:requirement]) { is_expected.to eq(req_string) }
    end

    context "with no requirement string (e.g., for a git dependency)" do
      let(:requirements) { [cargo_req] }

      let(:target_version) do
        "aa218f56b14c9653891f9e74264a383fa43fefbd"
      end
      let(:cargo_req) do
        {
          file: "Cargo.toml",
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/BurntSushi/utf8-ranges",
            branch: "master",
            ref: nil
          }
        }
      end
      let(:updated_source) do
        {
          type: "git",
          url: "https://github.com/BurntSushi/utf8-ranges",
          branch: "master",
          ref: nil
        }
      end
      it { is_expected.to eq(cargo_req) }

      context "when asked to update the source" do
        let(:updated_source) { { type: "git", ref: "v1.5.0" } }
        before { cargo_req.merge!(source: { type: "git", ref: "v1.2.0" }) }
        its([:source]) { is_expected.to eq(updated_source) }
      end
    end

    context "with a bump_versions strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

      context "when there is a latest version" do
        context "with a full version was previously specified" do
          let(:req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "with an equality requirement was previously specified" do
          let(:req_string) { "=1.2.3" }
          its([:requirement]) { is_expected.to eq("=1.5.0") }
        end

        context "with a partial version was previously specified" do
          let(:req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "with only the major part was previously specified" do
          let(:req_string) { "1" }
          let(:target_version) { "4.5.0" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with the new version has fewer digits than the old one" do
          let(:req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "with the new version has much fewer digits than the old one" do
          let(:req_string) { "1.1.0.1" }
          let(:target_version) { "4" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with a caret was previously specified" do
          let(:req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "with a pre-release was previously specified" do
          let(:req_string) { "^1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "when that needs updating" do
            let(:req_string) { "1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("1.5.0") }

            context "when to a new pre-release version" do
              let(:req_string) { "1.2.3-beta" }
              let(:target_version) { "1.2.3-beta.2" }
              its([:requirement]) { is_expected.to eq("1.2.3-beta.2") }
            end
          end
        end

        context "with just *" do
          let(:req_string) { "*" }
          its([:requirement]) { is_expected.to eq("*") }
        end

        context "with a < condition" do
          let(:req_string) { "< 1.2.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "with a < condition" do
          let(:req_string) { "> 99.2.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "with there were multiple range specifications" do
          let(:req_string) { "> 1.0.0, < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, < 1.6.0") }

          context "when already valid" do
            let(:req_string) { "> 1.0.0, < 1.7.0" }
            its([:requirement]) { is_expected.to eq(req_string) }
          end

          context "when that include a pre-release" do
            let(:req_string) { ">=1.2.0, <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0, <1.6.0") }
          end
        end

        context "with an *.* was previously specified" do
          let(:req_string) { "^0.*.*" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "with an *.* was previously specified with four places" do
          let(:req_string) { "^0.*.*.rc1" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "with there were multiple requirements" do
          let(:requirements) do
            [
              {
                file: "Cargo.toml",
                requirement: req_string,
                groups: [],
                source: nil
              },
              {
                file: "another/Cargo.toml",
                requirement: other_requirement_string,
                groups: [],
                source: nil
              }
            ]
          end
          let(:req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.*.*" }

          it "updates both requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "Cargo.toml",
                  requirement: "^1.5.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/Cargo.toml",
                  requirement: "^1.*.*",
                  groups: [],
                  source: nil
                }
              ]
            )
          end
        end

        context "with the target version has a build annotation" do
          let(:req_string) { "1.2.3" }
          let(:target_version) { "1.5.0+build.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end
      end
    end

    context "with a bump_versions_if_necessary strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

      context "when there is no latest version" do
        let(:target_version) { nil }
        its([:requirement]) { is_expected.to eq(req_string) }
      end

      context "when there is a latest version" do
        context "with a full version was previously specified" do
          let(:req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq(req_string) }
        end

        context "with an equality requirement was previously specified" do
          let(:req_string) { "=1.2.3" }
          its([:requirement]) { is_expected.to eq("=1.5.0") }
        end

        context "with a partial version was previously specified" do
          let(:req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "with only the major part was previously specified" do
          let(:req_string) { "1" }
          let(:target_version) { "4.5.0" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with the new version has fewer digits than the old one" do
          let(:req_string) { "0.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "with the new version has much fewer digits than the old one" do
          let(:req_string) { "1.1.0.1" }
          let(:target_version) { "4" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "with a caret was previously specified" do
          let(:req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq(req_string) }
        end

        context "with a pre-release was previously specified" do
          let(:req_string) { "^1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq(req_string) }

          context "when that needs updating" do
            let(:req_string) { "0.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("1.5.0") }

            context "when to a new pre-release version" do
              let(:req_string) { "0.2.3-beta" }
              let(:target_version) { "1.2.3-beta.2" }
              its([:requirement]) { is_expected.to eq("1.2.3-beta.2") }
            end
          end
        end

        context "with just *" do
          let(:req_string) { "*" }
          its([:requirement]) { is_expected.to eq("*") }
        end

        context "with a < condition" do
          let(:req_string) { "< 1.2.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "with a < condition" do
          let(:req_string) { "> 99.2.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "with there were multiple range specifications" do
          let(:req_string) { "> 1.0.0, < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, < 1.6.0") }

          context "when already valid" do
            let(:req_string) { "> 1.0.0, < 1.7.0" }
            its([:requirement]) { is_expected.to eq(req_string) }
          end

          context "when that include a pre-release" do
            let(:req_string) { ">=1.2.0, <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0, <1.6.0") }
          end
        end

        context "with an *.* was previously specified" do
          let(:req_string) { "^0.*.*" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "with an *.* was previously specified with four places" do
          let(:req_string) { "^0.*.*.rc1" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "with there were multiple requirements" do
          let(:requirements) do
            [
              {
                file: "Cargo.toml",
                requirement: req_string,
                groups: [],
                source: nil
              },
              {
                file: "another/Cargo.toml",
                requirement: other_requirement_string,
                groups: [],
                source: nil
              }
            ]
          end
          let(:req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.*.*" }

          it "updates only the required requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "Cargo.toml",
                  requirement: req_string,
                  groups: [],
                  source: nil
                },
                {
                  file: "another/Cargo.toml",
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

    context "with a lockfile_only strategy" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it "does not change any requirements" do
        expect(updater.updated_requirements).to eq(requirements)
      end
    end
  end
end
