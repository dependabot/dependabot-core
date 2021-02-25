# frozen_string_literal: true

require "spec_helper"
require "dependabot/haskell/update_checker/requirements_updater"

RSpec.describe Dependabot::Haskell::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      source_details: source_details
    )
  end

  let(:requirements) { [proj_req] }
  let(:proj_req) do
    {
      file: "Cabal.cabal",
      requirement: proj_req_string,
      groups: [],
      source: nil
    }
  end
  let(:proj_req_string) { "23.3-jre" }
  let(:latest_version) { version_class.new("23.6-jre") }
  let(:source_details) do
    {
      source_url: nil,
      repo_url: nil
    }
  end

  let(:version_class) { Dependabot::Haskell::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }
      it { is_expected.to eq(proj_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("23.6-jre") }

      context "and no requirement was previously specified" do
        let(:proj_req_string) { nil }
        it { is_expected.to eq(proj_req) }
      end

      context "and a soft requirement was previously specified" do
        let(:proj_req_string) { "23.3-jre" }
        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "and a hard requirement was previously specified" do
        let(:proj_req_string) { "[23.3-jre]" }
        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "and a suffixed requirement was previously specified" do
        let(:latest_version) do
          version_class.new("3.0.0-beta4.20210.2+38fe3493")
        end
        let(:proj_req_string) { "3.0.0-beta4.20207.4+07df2f07" }
        its([:requirement]) do
          is_expected.to eq("3.0.0-beta4.20210.2+38fe3493")
        end
      end

      context "and a wildcard requirement was previously specified" do
        let(:proj_req_string) { "22.*" }
        its([:requirement]) { is_expected.to eq("23.*") }

        context "for pre-release versions" do
          let(:proj_req_string) { "22.3-*" }
          its([:requirement]) { is_expected.to eq("23.6-*") }
        end

        context "that doesn't need updating" do
          let(:proj_req_string) { "23.*" }
          it { is_expected.to eq(proj_req) }
        end

        context "that is just a wildcard" do
          let(:proj_req_string) { "*" }
          it { is_expected.to eq(proj_req) }
        end
      end

      context "and there were multiple requirements" do
        let(:requirements) { [proj_req, other_proj_req] }

        let(:other_proj_req) do
          {
            file: "another/my.cabal",
            requirement: other_requirement_string,
            groups: [],
            source: nil
          }
        end
        let(:proj_req_string) { "23.3-jre" }
        let(:other_requirement_string) { "[23.4-jre]" }

        it "updates both requirements" do
          expect(updater.updated_requirements).to match_array(
            [{
              file: "my.cabal",
              requirement: "23.6-jre",
              groups: [],
              source: {
                type: "haskell",
                url: "https://api.haskell.org/v3/index.json",
                source_url: nil              }
            }, {
              file: "another/my.cabal",
              requirement: "[23.6-jre]",
              groups: [],
              source: {
                type: "haskell",
                url: "https://api.haskell.org/v3/index.json",
                source_url: nil              }
            }]
          )
        end

        context "and one is a range requirement" do
          let(:other_requirement_string) { "[23.0,)" }

          it "updates only the specific requirement" do
            expect(updater.updated_requirements).to match_array(
              [{
                file: "my.cabal",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "haskell",
                  url: "https://api.haskell.org/v3/index.json",
                  source_url: nil                }
              }, {
                file: "another/my.cabal",
                requirement: "[23.0,)",
                groups: [],
                source: nil
              }]
            )
          end
        end
      end
    end
  end
end
