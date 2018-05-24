# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java/maven/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Java::Maven::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      source_url: "new_url",
      properties_to_update: []
    )
  end

  let(:requirements) { [pom_req] }
  let(:pom_req) do
    {
      file: "pom.xml",
      requirement: pom_req_string,
      groups: [],
      source: nil
    }
  end
  let(:pom_req_string) { "23.3-jre" }
  let(:latest_version) { version_class.new("23.6-jre") }

  let(:version_class) { Dependabot::Utils::Java::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }
      it { is_expected.to eq(pom_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("23.6-jre") }

      context "and no requirement was previously specified" do
        let(:pom_req_string) { nil }
        it { is_expected.to eq(pom_req) }
      end

      context "and a soft requirement was previously specified" do
        let(:pom_req_string) { "23.3-jre" }
        its([:requirement]) { is_expected.to eq("23.6-jre") }
        its([:source]) { is_expected.to eq(type: "maven_repo", url: "new_url") }
      end

      context "and the version included capitals" do
        let(:pom_req_string) { "23.3.RELEASE" }
        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "and a hard requirement was previously specified" do
        let(:pom_req_string) { "[23.3-jre]" }
        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "and there were multiple requirements" do
        let(:requirements) { [pom_req, other_pom_req] }

        let(:other_pom_req) do
          {
            file: "another/pom.xml",
            requirement: other_requirement_string,
            groups: [],
            source: nil
          }
        end
        let(:pom_req_string) { "23.3-jre" }
        let(:other_requirement_string) { "[23.4-jre]" }

        it "updates both requirements" do
          expect(updater.updated_requirements).to match_array(
            [
              {
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: { type: "maven_repo", url: "new_url" }
              },
              {
                file: "another/pom.xml",
                requirement: "[23.6-jre]",
                groups: [],
                source: { type: "maven_repo", url: "new_url" }
              }
            ]
          )
        end

        context "and one is a range requirement" do
          let(:other_requirement_string) { "[23.0,)" }

          it "updates only the specific requirement" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: { type: "maven_repo", url: "new_url" }
                },
                {
                  file: "another/pom.xml",
                  requirement: "[23.0,)",
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
