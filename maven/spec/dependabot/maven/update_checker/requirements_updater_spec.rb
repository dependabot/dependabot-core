# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/update_checker/requirements_updater"

RSpec.describe Dependabot::Maven::UpdateChecker::RequirementsUpdater do
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

  let(:version_class) { Dependabot::Maven::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }

      it { is_expected.to eq(pom_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("23.6-jre") }

      context "when there is no requirement was previously specified" do
        let(:pom_req_string) { nil }

        it { is_expected.to eq(pom_req) }
      end

      context "when a LATEST requirement was previously specified" do
        let(:pom_req_string) { "LATEST" }

        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "when a soft requirement was previously specified" do
        let(:pom_req_string) { "23.3-jre" }

        its([:requirement]) { is_expected.to eq("23.6-jre") }
        its([:source]) { is_expected.to eq(type: "maven_repo", url: "new_url") }

        context "when including multiple dashes" do
          let(:pom_req_string) { "v2-rev398-1.24.1" }
          let(:latest_version) { version_class.new("v2-rev404-1.25.0") }

          its([:requirement]) { is_expected.to eq("v2-rev404-1.25.0") }
        end
      end

      context "when the latest version matches the current requirement" do
        let(:pom_req_string) { "23.6-jre" }
        let(:latest_version) { version_class.new("23.6-jre") }

        it "does not update the requirement or source" do
          expect(updater.updated_requirements.first).to eq(pom_req)
        end
      end

      context "when only source metadata differs but requirement is unchanged" do
        let(:pom_req) do
          {
            file: "pom.xml",
            requirement: "1.46.0",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }
        end
        let(:pom_req_string) { "1.46.0" }
        let(:latest_version) { version_class.new("1.46.0") }

        it "returns the original requirement without updating source" do
          result = updater.updated_requirements.first
          expect(result).to eq(pom_req)
          expect(result[:source]).to be_nil
        end
      end

      context "when the version is including capitals" do
        let(:pom_req_string) { "23.3.RELEASE" }

        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "when a hard requirement was previously specified" do
        let(:pom_req_string) { "[23.3-jre]" }

        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "when there were multiple requirements" do
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
          expect(updater.updated_requirements).to contain_exactly(
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
              source: { type: "maven_repo",
                        url: "new_url" }
            }
          )
        end

        context "when one is a range requirement" do
          let(:other_requirement_string) { "[23.0,)" }

          it "updates only the specific requirement" do
            expect(updater.updated_requirements).to contain_exactly(
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
            )
          end
        end

        context "when one requirement is already at the latest version" do
          let(:pom_req_string) { "23.6-jre" }
          let(:other_requirement_string) { "23.3-jre" }

          it "only updates the outdated requirement" do
            expect(updater.updated_requirements).to contain_exactly(
              {
                file: "pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: nil
              },
              {
                file: "another/pom.xml",
                requirement: "23.6-jre",
                groups: [],
                source: { type: "maven_repo", url: "new_url" }
              }
            )
          end
        end
      end
    end
  end
end
