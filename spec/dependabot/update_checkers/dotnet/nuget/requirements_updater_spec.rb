# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/dotnet/nuget/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Dotnet::Nuget::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      source_details: source_details
    )
  end

  let(:requirements) { [csproj_req] }
  let(:csproj_req) do
    {
      file: "my.csproj",
      requirement: csproj_req_string,
      groups: [],
      source: nil
    }
  end
  let(:csproj_req_string) { "23.3-jre" }
  let(:latest_version) { version_class.new("23.6-jre") }
  let(:source_details) do
    {
      repo_url:   "https://api.nuget.org/v3/index.json",
      nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                  "microsoft.extensions.dependencymodel/1.2.3/"\
                  "microsoft.extensions.dependencymodel.nuspec"
    }
  end

  let(:version_class) { Dependabot::Utils::Dotnet::Version }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }
      it { is_expected.to eq(csproj_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("23.6-jre") }

      context "and no requirement was previously specified" do
        let(:csproj_req_string) { nil }
        it { is_expected.to eq(csproj_req) }
      end

      context "and a soft requirement was previously specified" do
        let(:csproj_req_string) { "23.3-jre" }
        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "and a hard requirement was previously specified" do
        let(:csproj_req_string) { "[23.3-jre]" }
        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "and there were multiple requirements" do
        let(:requirements) { [csproj_req, other_csproj_req] }

        let(:other_csproj_req) do
          {
            file: "another/my.csproj",
            requirement: other_requirement_string,
            groups: [],
            source: nil
          }
        end
        let(:csproj_req_string) { "23.3-jre" }
        let(:other_requirement_string) { "[23.4-jre]" }

        it "updates both requirements" do
          expect(updater.updated_requirements).to match_array(
            [
              {
                file: "my.csproj",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "nuget_repo",
                  url: "https://api.nuget.org/v3/index.json",
                  nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                              "microsoft.extensions.dependencymodel/1.2.3/"\
                              "microsoft.extensions.dependencymodel.nuspec"
                }
              },
              {
                file: "another/my.csproj",
                requirement: "[23.6-jre]",
                groups: [],
                source: {
                  type: "nuget_repo",
                  url: "https://api.nuget.org/v3/index.json",
                  nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                              "microsoft.extensions.dependencymodel/1.2.3/"\
                              "microsoft.extensions.dependencymodel.nuspec"
                }
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
                  file: "my.csproj",
                  requirement: "23.6-jre",
                  groups: [],
                  source: {
                    type: "nuget_repo",
                    url: "https://api.nuget.org/v3/index.json",
                    nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                                "microsoft.extensions.dependencymodel/1.2.3/"\
                                "microsoft.extensions.dependencymodel.nuspec"
                  }
                },
                {
                  file: "another/my.csproj",
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
