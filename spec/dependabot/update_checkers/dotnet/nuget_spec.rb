# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/dotnet/nuget"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Dotnet::Nuget do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end
  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "1.1.1", groups: [], source: nil }]
  end
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:dependency_version) { "1.1.1" }

  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) { fixture("dotnet", "csproj", "basic.csproj") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }

  let(:nuget_versions_url) do
    "https://api.nuget.org/v3-flatcontainer/"\
    "microsoft.extensions.dependencymodel/index.json"
  end
  let(:nuget_search_url) do
    "https://api-v2v3search-0.nuget.org/query"\
    "?q=microsoft.extensions.dependencymodel&prerelease=true"
  end
  let(:version_class) { Dependabot::Utils::Dotnet::Version }
  let(:nuget_versions) do
    fixture("dotnet", "nuget_responses", "versions.json")
  end
  let(:nuget_search_results) do
    fixture("dotnet", "nuget_responses", "search_results.json")
  end

  before do
    stub_request(:get, nuget_versions_url).
      to_return(status: 200, body: nuget_versions)
    stub_request(:get, nuget_search_url).
      to_return(status: 200, body: nuget_search_results)
  end

  describe "up_to_date?" do
    subject(:up_to_date?) { checker.up_to_date? }

    context "with a property dependency" do
      context "whose property couldn't be found" do
        let(:dependency_name) { "Nuke.Common" }
        let(:dependency_requirements) do
          [{
            requirement: "$(NukeVersion)",
            file: "my.csproj",
            groups: [],
            source: nil,
            metadata: { property_name: "NukeVersion" }
          }]
        end
        let(:dependency_version) { "$(NukeVersion)" }

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(version_class.new("2.1.0")) }

    it "delegates to the VersionFinder class" do
      version_finder_class = described_class::VersionFinder
      dummy_version_finder = instance_double(version_finder_class)
      allow(version_finder_class).
        to receive(:new).
        and_return(dummy_version_finder)
      allow(dummy_version_finder).
        to receive(:latest_version_details).
        and_return(version: "dummy_version")

      expect(checker.latest_version).to eq("dummy_version")
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "delegates to latest_version" do
      expect(checker).to receive(:latest_version).and_return("latest_version")
      expect(latest_resolvable_version).to eq("latest_version")
    end

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: [],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      context "that is used for multiple dependencies" do
        let(:csproj_body) do
          fixture("dotnet", "csproj", "property_version.csproj")
        end

        it "does not delegate to latest_version" do
          expect(checker).to_not receive(:latest_version)
          expect(latest_resolvable_version).to be_nil
        end
      end

      context "that is used for a single dependencies" do
        let(:csproj_body) do
          fixture("dotnet", "csproj", "single_dep_property_version.csproj")
        end

        it "delegates to latest_version" do
          expect(checker).to receive(:latest_version).
            and_return("latest_version")
          expect(latest_resolvable_version).to eq("latest_version")
        end
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }
    it { is_expected.to be_nil }
  end

  describe "#can_update?(requirements_to_unlock: :all)" do
    subject(:can_update) { checker.can_update?(requirements_to_unlock: :all) }

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: [],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }
      let(:nuget_search_url) do
        "https://api-v2v3search-0.nuget.org/query"\
        "?q=nuke.common&prerelease=true"
      end
      let(:nuget_search_results) do
        fixture(
          "dotnet", "nuget_responses", "search_result_nuke_common.json"
        )
      end

      context "that is used for multiple dependencies" do
        let(:csproj_body) do
          fixture("dotnet", "csproj", "property_version.csproj")
        end

        context "where all dependencies can update to the latest version" do
          before do
            codegeneration_search_url =
              "https://api-v2v3search-0.nuget.org/query"\
              "?q=nuke.codegeneration&prerelease=true"

            codegeneration_search_result =
              fixture(
                "dotnet",
                "nuget_responses",
                "search_result_nuke_codegeneration.json"
              )
            stub_request(:get, codegeneration_search_url).
              to_return(status: 200, body: codegeneration_search_result)
          end

          it { is_expected.to eq(true) }
        end

        context "where not all dependencies can update to the latest version" do
          before do
            codegeneration_search_url =
              "https://api-v2v3search-0.nuget.org/query"\
              "?q=nuke.codegeneration&prerelease=true"

            codegeneration_search_result =
              fixture(
                "dotnet",
                "nuget_responses",
                "search_result_nuke_codegeneration.json"
              ).gsub("0.9.0", "0.8.9")
            stub_request(:get, codegeneration_search_url).
              to_return(status: 200, body: codegeneration_search_result)
          end

          it { is_expected.to eq(false) }
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).to receive(:new).with(
        requirements: dependency_requirements,
        latest_version: "2.1.0",
        source_details: {
          source_url: nil,
          nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                      "microsoft.extensions.dependencymodel/2.1.0/"\
                      "microsoft.extensions.dependencymodel.nuspec",
          repo_url: "https://api.nuget.org/v3/index.json"
        }
      ).and_call_original
      expect(updated_requirements).to eq(
        [{
          file: "my.csproj",
          requirement: "2.1.0",
          groups: [],
          source: {
            type: "nuget_repo",
            url: "https://api.nuget.org/v3/index.json",
            source_url: nil,
            nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                        "microsoft.extensions.dependencymodel/2.1.0/"\
                        "microsoft.extensions.dependencymodel.nuspec"
          }
        }]
      )
    end

    context "with a custom repo in a nuget.config file" do
      let(:config_file) do
        Dependabot::DependencyFile.new(
          name: "NuGet.Config",
          content: fixture("dotnet", "configs", "nuget.config")
        )
      end
      let(:dependency_files) { [csproj, config_file] }

      context "that uses the v2 API" do
        let(:config_file) do
          Dependabot::DependencyFile.new(
            name: "NuGet.Config",
            content: fixture("dotnet", "configs", "with_v2_endpoints.config")
          )
        end

        before do
          v2_repo_urls = %w(
            https://www.nuget.org/api/v2/
            https://www.myget.org/F/azure-appservice/api/v2
            https://www.myget.org/F/azure-appservice-staging/api/v2
            https://www.myget.org/F/fusemandistfeed/api/v2
            https://www.myget.org/F/30de4ee06dd54956a82013fa17a3accb/
          )

          v2_repo_urls.each do |repo_url|
            stub_request(:get, repo_url).
              to_return(
                status: 200,
                body: fixture("dotnet", "nuget_responses", "v2_base.xml")
              )
          end

          url = "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json"
          stub_request(:get, url).
            to_return(
              status: 200,
              body: fixture("dotnet", "nuget_responses", "myget_base.json")
            )

          custom_v3_nuget_versions_url =
            "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/"\
            "microsoft.extensions.dependencymodel/index.json"
          stub_request(:get, custom_v3_nuget_versions_url).
            to_return(status: 404)
          custom_v3_nuget_search_url =
            "https://www.myget.org/F/exceptionless/api/v3/"\
            "query?q=microsoft.extensions.dependencymodel&prerelease=true"
          stub_request(:get, custom_v3_nuget_search_url).
            to_return(status: 404)

          custom_v2_nuget_versions_url =
            "https://www.nuget.org/api/v2/FindPackagesById()?id="\
            "'Microsoft.Extensions.DependencyModel'"
          stub_request(:get, custom_v2_nuget_versions_url).
            to_return(
              status: 200,
              body: fixture("dotnet", "nuget_responses", "v2_versions.xml")
            )
        end

        it "delegates to the RequirementsUpdater" do
          expect(described_class::RequirementsUpdater).to receive(:new).with(
            requirements: dependency_requirements,
            latest_version: "4.8.1",
            source_details: {
              nuspec_url: nil,
              repo_url: "https://www.nuget.org/api/v2",
              source_url: "https://github.com/autofac/Autofac"
            }
          ).and_call_original
          expect(updated_requirements).to eq(
            [{
              file: "my.csproj",
              requirement: "4.8.1",
              groups: [],
              source: {
                type: "nuget_repo",
                url: "https://www.nuget.org/api/v2",
                source_url: "https://github.com/autofac/Autofac",
                nuspec_url: nil
              }
            }]
          )
        end
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject(:requirements_unlocked_or_can_be) do
      checker.requirements_unlocked_or_can_be?
    end

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: [],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }

      it { is_expected.to eq(true) }

      context "whose property couldn't be found" do
        let(:dependency_requirements) do
          [{
            requirement: "$(NukeVersion)",
            file: "my.csproj",
            groups: [],
            source: nil,
            metadata: { property_name: "NukeVersion" }
          }]
        end
        let(:dependency_version) { "$(NukeVersion)" }

        it { is_expected.to eq(false) }
      end
    end
  end

  describe "#updated_dependencies(requirements_to_unlock: :all)" do
    subject(:updated_dependencies) do
      checker.updated_dependencies(requirements_to_unlock: :all)
    end

    context "with a property dependency" do
      let(:dependency_requirements) do
        [{
          requirement: "0.1.434",
          file: "my.csproj",
          groups: [],
          source: nil,
          metadata: { property_name: "NukeVersion" }
        }]
      end
      let(:dependency_name) { "Nuke.Common" }
      let(:dependency_version) { "0.1.434" }
      let(:nuget_search_url) do
        "https://api-v2v3search-0.nuget.org/query"\
        "?q=nuke.common&prerelease=true"
      end
      let(:nuget_search_results) do
        fixture(
          "dotnet", "nuget_responses", "search_result_nuke_common.json"
        )
      end

      context "that is used for multiple dependencies" do
        let(:csproj_body) do
          fixture("dotnet", "csproj", "property_version.csproj")
        end

        context "where all dependencies can update to the latest version" do
          before do
            codegeneration_search_url =
              "https://api-v2v3search-0.nuget.org/query"\
              "?q=nuke.codegeneration&prerelease=true"

            codegeneration_search_result =
              fixture(
                "dotnet",
                "nuget_responses",
                "search_result_nuke_codegeneration.json"
              )
            stub_request(:get, codegeneration_search_url).
              to_return(status: 200, body: codegeneration_search_result)
          end

          it "gives the correct array of dependencies" do
            expect(updated_dependencies).to eq(
              [
                Dependabot::Dependency.new(
                  name: "Nuke.Common",
                  version: "0.9.0",
                  previous_version: "0.1.434",
                  requirements: [{
                    requirement: "0.9.0",
                    file: "my.csproj",
                    groups: [],
                    source: {
                      type: "nuget_repo",
                      url: "https://api.nuget.org/v3/index.json",
                      nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                                  "nuke.common/0.9.0/nuke.common.nuspec",
                      source_url: nil
                    },
                    metadata: { property_name: "NukeVersion" }
                  }],
                  previous_requirements: [{
                    requirement: "0.1.434",
                    file: "my.csproj",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "NukeVersion" }
                  }],
                  package_manager: "nuget"
                ),
                Dependabot::Dependency.new(
                  name: "Nuke.CodeGeneration",
                  version: "0.9.0",
                  previous_version: "0.1.434",
                  requirements: [{
                    requirement: "0.9.0",
                    file: "my.csproj",
                    groups: [],
                    source: {
                      type: "nuget_repo",
                      url: "https://api.nuget.org/v3/index.json",
                      nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                                  "nuke.common/0.9.0/nuke.common.nuspec",
                      source_url: nil
                    },
                    metadata: { property_name: "NukeVersion" }
                  }],
                  previous_requirements: [{
                    requirement: "0.1.434",
                    file: "my.csproj",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "NukeVersion" }
                  }],
                  package_manager: "nuget"
                )
              ]
            )
          end
        end
      end
    end
  end
end
