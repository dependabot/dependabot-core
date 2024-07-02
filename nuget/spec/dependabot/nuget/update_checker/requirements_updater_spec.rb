# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/update_checker/requirements_updater"

RSpec.describe Dependabot::Nuget::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      dependency_details: dependency_details
    )
  end

  let(:requirements) { [csproj_req] }
  let(:csproj_req) do
    {
      file: "my.csproj",
      requirement: csproj_req_string,
      groups: ["dependencies"],
      source: nil
    }
  end
  let(:csproj_req_string) { "23.3-jre" }
  let(:latest_version) { "23.6-jre" }
  let(:info_url) { "https://nuget.example.com/some.package" }
  # let(:source_details) do
  #   {
  #     source_url: nil,
  #     repo_url: "https://api.nuget.org/v3/index.json",
  #     nuspec_url: "https://api.nuget.org/v3-flatcontainer/" \
  #                 "microsoft.extensions.dependencymodel/1.2.3/" \
  #                 "microsoft.extensions.dependencymodel.nuspec"
  #   }
  # end
  let(:dependency_details) do
    Dependabot::Nuget::DependencyDetails.from_json(JSON.parse({
      Name: "unused",
      Version: latest_version,
      Type: "PackageReference",
      EvaluationResult: nil,
      TargetFrameworks: nil,
      IsDevDependency: false,
      IsDirect: true,
      IsTransitive: false,
      IsOverride: false,
      IsUpdate: false,
      InfoUrl: info_url
    }.to_json))
  end

  # let(:version_class) { Dependabot::Nuget::Version }

  describe "#updated_requirements.version" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }

      it { is_expected.to eq(csproj_req) }
    end

    context "when there is a latest version" do
      let(:latest_version) { "23.6-jre" }

      context "when no requirement was previously specified" do
        let(:csproj_req_string) { nil }

        it { is_expected.to eq(csproj_req) }
      end

      context "when a soft requirement was previously specified" do
        let(:csproj_req_string) { "23.3-jre" }

        its([:requirement]) { is_expected.to eq("23.6-jre") }
      end

      context "when a hard requirement was previously specified" do
        let(:csproj_req_string) { "[23.3-jre]" }

        its([:requirement]) { is_expected.to eq("[23.6-jre]") }
      end

      context "when a suffixed requirement was previously specified" do
        let(:latest_version) { "3.0.0-beta4.20210.2+38fe3493" }
        let(:csproj_req_string) { "3.0.0-beta4.20207.4+07df2f07" }

        its([:requirement]) do
          is_expected.to eq("3.0.0-beta4.20210.2")
        end
      end

      context "when a wildcard requirement was previously specified" do
        let(:csproj_req_string) { "22.*" }

        its([:requirement]) { is_expected.to eq("23.*") }

        context "when dealing with a pre-release versions" do
          let(:csproj_req_string) { "22.3-*" }

          its([:requirement]) { is_expected.to eq("23.6-*") }
        end

        context "when the requirement need not to be updated" do
          let(:csproj_req_string) { "23.*" }

          it { is_expected.to eq(csproj_req) }
        end

        context "when the requirement is just a wildcard" do
          let(:csproj_req_string) { "*" }

          it { is_expected.to eq(csproj_req) }
        end
      end

      context "when there were multiple requirements" do
        let(:requirements) { [csproj_req, other_csproj_req] }

        let(:other_csproj_req) do
          {
            file: "another/my.csproj",
            requirement: other_requirement_string,
            groups: ["dependencies"],
            source: nil
          }
        end
        let(:csproj_req_string) { "23.3-jre" }
        let(:other_requirement_string) { "[23.4-jre]" }

        it "updates both requirements" do
          expect(updater.updated_requirements).to contain_exactly({
            file: "my.csproj",
            requirement: "23.6-jre",
            groups: ["dependencies"],
            source: {
              type: "nuget_repo",
              source_url: "https://nuget.example.com/some.package"
            }
          }, {
            file: "another/my.csproj",
            requirement: "[23.6-jre]",
            groups: ["dependencies"],
            source: {
              type: "nuget_repo",
              source_url: "https://nuget.example.com/some.package"
            }
          })
        end

        context "when one is a range requirement" do
          let(:other_requirement_string) { "[23.0,)" }

          it "updates only the specific requirement" do
            expect(updater.updated_requirements).to contain_exactly({
              file: "my.csproj",
              requirement: "23.6-jre",
              groups: ["dependencies"],
              source: {
                type: "nuget_repo",
                source_url: "https://nuget.example.com/some.package"
              }
            }, {
              file: "another/my.csproj",
              requirement: "[23.0,)",
              groups: ["dependencies"],
              source: nil
            })
          end
        end
      end
    end
  end
end
