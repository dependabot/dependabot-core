# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/rust/cargo/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Rust::Cargo::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      library: library,
      latest_version: latest_version
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

  let(:library) { false }
  let(:latest_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:req_string) { "^1.0.0" }

    context "when there is no latest version" do
      let(:latest_version) { nil }
      its([:requirement]) { is_expected.to eq(req_string) }
    end

    context "with no requirement string (e.g., for a git dependency)" do
      let(:req_string) { nil }
      its([:requirement]) { is_expected.to eq(nil) }
    end

    context "for an app requirement" do
      let(:library) { false }

      context "when there is a latest version" do
        context "and a full version was previously specified" do
          let(:req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:req_string) { "1" }
          let(:latest_version) { "4.5.0" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:req_string) { "1.1.0.1" }
          let(:latest_version) { "4" }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          let(:req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:req_string) { "^1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }

          context "that needs updating" do
            let(:req_string) { "1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("1.5.0") }

            context "to a new pre-release version" do
              let(:req_string) { "1.2.3-beta" }
              let(:latest_version) { "1.2.3-beta.2" }
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

        context "and there were multiple range specifications" do
          let(:req_string) { "> 1.0.0, < 1.2.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, < 1.6.0") }

          context "already valid" do
            let(:req_string) { "> 1.0.0, < 1.7.0" }
            its([:requirement]) { is_expected.to eq(req_string) }
          end

          context "that include a pre-release" do
            let(:req_string) { ">=1.2.0, <1.4.0-dev" }
            its([:requirement]) { is_expected.to eq(">=1.2.0, <1.6.0") }
          end
        end

        context "and an *.* was previously specified" do
          let(:req_string) { "^0.*.*" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "and an *.* was previously specified with four places" do
          let(:req_string) { "^0.*.*.rc1" }
          its([:requirement]) { is_expected.to eq("^1.*.*") }
        end

        context "and there were multiple requirements" do
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
      end
    end
  end
end
