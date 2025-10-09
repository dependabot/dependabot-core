# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/update_checker/requirements_updater"

RSpec.describe Dependabot::Gradle::UpdateChecker::RequirementsUpdater do
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

  let(:version_class) { Dependabot::Gradle::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }

      it { is_expected.to eq(pom_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("23.6-jre") }

      context "when no requirement was previously specified" do
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

        context "when the requirement includes multiple dashes" do
          let(:pom_req_string) { "v2-rev398-1.24.1" }
          let(:latest_version) { version_class.new("v2-rev404-1.25.0") }

          its([:requirement]) { is_expected.to eq("v2-rev404-1.25.0") }
        end
      end

      context "when the requirement includes uppercase letters" do
        let(:pom_req_string) { "23.3.RELEASE" }

        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "when a hard requirement was previously specified" do
        let(:pom_req_string) { "[23.3-jre]" }

        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "when a dynamic requirement was previously specified" do
        let(:pom_req_string) { "22.+" }

        its([:requirement]) { is_expected.to eq("23.+") }

        context "when the requirement omits the dot before the plus" do
          let(:pom_req_string) { "22.1+" }

          its([:requirement]) { is_expected.to eq("23.6+") }
        end

        context "when the requirement is just a plus" do
          let(:pom_req_string) { "+" }

          its([:requirement]) { is_expected.to eq("+") }
        end
      end

      context "when there are multiple requirements" do
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
      end
    end

    context "with distribution dependency" do
      let(:requirements) { [distribution_req, checksum_req] }
      let(:latest_version) { version_class.new("9.0.0") }

      let(:distribution_req) do
        {
          requirement: "8.14.2",
          file: "gradle/wrapper/gradle-wrapper.properties",
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-8.14.2-all.zip",
            property: "distributionUrl"
          },
          groups: []
        }
      end

      let(:checksum_req) do
        {
          requirement: "443c9c8ee2ac1ee0e11881a40f2376d79c66386264a44b24a9f8ca67e633375f",
          file: "gradle/wrapper/gradle-wrapper.properties",
          source: {
            type: "gradle-distribution",
            url: "https://services.gradle.org/distributions/gradle-8.14.2-all.zip.sha256",
            property: "distributionSha256Sum"
          },
          groups: []
        }
      end

      before do
        stub_request(:get, "https://services.gradle.org/distributions/gradle-9.0.0-all.zip.sha256")
          .to_return(status: 200, body: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365")
      end

      it "updates url and checksum" do
        expect(updater.updated_requirements).not_to eq(requirements)
        expect(updater.updated_requirements).to eq(
          [
            {
              requirement: "9.0.0",
              file: "gradle/wrapper/gradle-wrapper.properties",
              source: {
                type: "gradle-distribution",
                url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip",
                property: "distributionUrl"
              },
              groups: []
            },
            {
              requirement: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365",
              file: "gradle/wrapper/gradle-wrapper.properties",
              source: {
                type: "gradle-distribution",
                url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip.sha256",
                property: "distributionSha256Sum"
              },
              groups: []
            }
          ]
        )
      end

      context "when no checksum is available" do
        let(:requirements) { [distribution_req] }

        it "only updates url" do
          expect(updater.updated_requirements).not_to eq(requirements)
          expect(updater.updated_requirements).to eq(
            [
              {
                requirement: "9.0.0",
                file: "gradle/wrapper/gradle-wrapper.properties",
                source: {
                  type: "gradle-distribution",
                  url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip",
                  property: "distributionUrl"
                },
                groups: []
              }
            ]
          )
        end
      end

      context "when multiple properties files" do
        let(:requirements) do
          [distribution_req, checksum_req, distribution_req.merge(
            requirement: "8.14.3",
            file: "another/gradle/wrapper/gradle-wrapper.properties",
            source: distribution_req[:source].merge(
              {
                url: "https://services.gradle.org/distributions/gradle-8.14.3-bin.zip"
              }
            )
          ), checksum_req.merge(
            requirement: "bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531",
            file: "another/gradle/wrapper/gradle-wrapper.properties",
            source: checksum_req[:source].merge(
              {
                url: "https://services.gradle.org/distributions/gradle-8.14.3-bin.zip.sha256"
              }
            )
          )]
        end

        before do
          stub_request(:get, "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip.sha256")
            .to_return(status: 200, body: "8fad3d78296ca518113f3d29016617c7f9367dc005f932bd9d93bf45ba46072b")
        end

        it "updates all of them" do
          expect(updater.updated_requirements).not_to eq(requirements)
          expect(updater.updated_requirements).to eq(
            [
              {
                requirement: "9.0.0",
                file: "gradle/wrapper/gradle-wrapper.properties",
                source: {
                  type: "gradle-distribution",
                  url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip",
                  property: "distributionUrl"
                },
                groups: []
              }, {
                requirement: "f759b8dd5204e2e3fa4ca3e73f452f087153cf81bac9561eeb854229cc2c5365",
                file: "gradle/wrapper/gradle-wrapper.properties",
                source: {
                  type: "gradle-distribution",
                  url: "https://services.gradle.org/distributions/gradle-9.0.0-all.zip.sha256",
                  property: "distributionSha256Sum"
                },
                groups: []
              }, {
                requirement: "9.0.0",
                file: "another/gradle/wrapper/gradle-wrapper.properties",
                source: {
                  type: "gradle-distribution",
                  url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip",
                  property: "distributionUrl"
                },
                groups: []
              }, {
                requirement: "8fad3d78296ca518113f3d29016617c7f9367dc005f932bd9d93bf45ba46072b",
                file: "another/gradle/wrapper/gradle-wrapper.properties",
                source: {
                  type: "gradle-distribution",
                  url: "https://services.gradle.org/distributions/gradle-9.0.0-bin.zip.sha256",
                  property: "distributionSha256Sum"
                },
                groups: []
              }
            ]
          )
        end
      end
    end
  end
end
