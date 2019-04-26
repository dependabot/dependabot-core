# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/version_finder"

RSpec.describe Dependabot::Nuget::UpdateChecker::VersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
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
  let(:csproj_body) { fixture("csproj", "basic.csproj") }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  let(:nuget_versions_url) do
    "https://api.nuget.org/v3-flatcontainer/"\
    "microsoft.extensions.dependencymodel/index.json"
  end
  let(:nuget_search_url) do
    "https://api-v2v3search-0.nuget.org/query"\
    "?q=microsoft.extensions.dependencymodel&prerelease=true"
  end
  let(:version_class) { Dependabot::Nuget::Version }
  let(:nuget_versions) do
    fixture("nuget_responses", "versions.json")
  end
  let(:nuget_search_results) do
    fixture("nuget_responses", "search_results.json")
  end

  before do
    stub_request(:get, nuget_versions_url).
      to_return(status: 200, body: nuget_versions)
    stub_request(:get, nuget_search_url).
      to_return(status: 200, body: nuget_search_results)
  end

  describe "#latest_version_details" do
    subject(:latest_version_details) { finder.latest_version_details }
    its([:version]) { is_expected.to eq(version_class.new("2.1.0")) }

    context "when the user wants a pre-release" do
      let(:dependency_version) { "2.2.0-preview1-26216-03" }
      its([:version]) do
        is_expected.to eq(version_class.new("2.2.0-preview2-26406-04"))
      end

      context "for a previous version" do
        let(:dependency_version) { "2.1.0-preview1-26216-03" }
        its([:version]) do
          is_expected.to eq(version_class.new("2.1.0"))
        end
      end
    end

    context "when the user is using an unfound property" do
      let(:dependency_version) { "$PackageVersion_LibGit2SharpNativeBinaries" }
      its([:version]) { is_expected.to eq(version_class.new("2.1.0")) }
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 2.a, < 3.0.0"] }
      its([:version]) { is_expected.to eq(version_class.new("1.1.2")) }
    end

    context "with a custom repo in a nuget.config file" do
      let(:config_file) do
        Dependabot::DependencyFile.new(
          name: "NuGet.Config",
          content: fixture("configs", "nuget.config")
        )
      end
      let(:dependency_files) { [csproj, config_file] }
      let(:custom_repo_url) do
        "https://www.myget.org/F/exceptionless/api/v3/index.json"
      end
      before do
        stub_request(:get, nuget_versions_url).to_return(status: 404)
        stub_request(:get, nuget_search_url).to_return(status: 404)

        stub_request(:get, custom_repo_url).to_return(status: 404)
        stub_request(:get, custom_repo_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(
            status: 200,
            body: fixture("nuget_responses", "myget_base.json")
          )
        custom_nuget_versions_url =
          "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/"\
          "microsoft.extensions.dependencymodel/index.json"
        custom_nuget_search_url =
          "https://www.myget.org/F/exceptionless/api/v3/"\
          "query?q=microsoft.extensions.dependencymodel&prerelease=true"
        stub_request(:get, custom_nuget_versions_url).to_return(status: 404)
        stub_request(:get, custom_nuget_versions_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(status: 200, body: nuget_versions)
        stub_request(:get, custom_nuget_search_url).to_return(status: 404)
        stub_request(:get, custom_nuget_search_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(status: 200, body: nuget_search_results)
      end

      its([:version]) { is_expected.to eq(version_class.new("2.1.0")) }

      context "that uses the v2 API" do
        let(:config_file) do
          Dependabot::DependencyFile.new(
            name: "NuGet.Config",
            content: fixture("configs", "with_v2_endpoints.config")
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
                body: fixture("nuget_responses", "v2_base.xml")
              )
          end

          url = "https://dotnet.myget.org/F/aspnetcore-dev/api/v3/index.json"
          stub_request(:get, url).
            to_return(
              status: 200,
              body: fixture("nuget_responses", "myget_base.json")
            )

          custom_v3_nuget_versions_url =
            "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/"\
            "microsoft.extensions.dependencymodel/index.json"
          stub_request(:get, custom_v3_nuget_versions_url).
            to_return(status: 404)

          custom_v2_nuget_versions_url =
            "https://www.nuget.org/api/v2/FindPackagesById()?id="\
            "'Microsoft.Extensions.DependencyModel'"
          stub_request(:get, custom_v2_nuget_versions_url).
            to_return(
              status: 200,
              body: fixture("nuget_responses", "v2_versions.xml")
            )
        end

        its([:version]) { is_expected.to eq(version_class.new("4.8.1")) }
      end
    end

    context "with a custom repo in the credentials" do
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "nuget_feed",
          "url" => custom_repo_url,
          "token" => "my:passw0rd"
        }]
      end
      let(:custom_repo_url) do
        "https://www.myget.org/F/exceptionless/api/v3/index.json"
      end
      before do
        stub_request(:get, nuget_versions_url).to_return(status: 404)
        stub_request(:get, nuget_search_url).to_return(status: 404)

        stub_request(:get, custom_repo_url).to_return(status: 404)
        stub_request(:get, custom_repo_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(
            status: 200,
            body: fixture("nuget_responses", "myget_base.json")
          )
        custom_nuget_versions_url =
          "https://www.myget.org/F/exceptionless/api/v3/flatcontainer/"\
          "microsoft.extensions.dependencymodel/index.json"
        custom_nuget_search_url =
          "https://www.myget.org/F/exceptionless/api/v3/"\
          "query?q=microsoft.extensions.dependencymodel&prerelease=true"
        stub_request(:get, custom_nuget_versions_url).to_return(status: 404)
        stub_request(:get, custom_nuget_versions_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(status: 200, body: nuget_versions)
        stub_request(:get, custom_nuget_search_url).to_return(status: 404)
        stub_request(:get, custom_nuget_search_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(status: 200, body: nuget_search_results)
      end

      its([:version]) { is_expected.to eq(version_class.new("2.1.0")) }
    end
  end

  describe "#lowest_security_fix_version_details" do
    subject(:lowest_security_fix_version_details) do
      finder.lowest_security_fix_version_details
    end

    let(:dependency_version) { "1.1.1" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: "rails",
          package_manager: "nuget",
          vulnerable_versions: ["< 2.0.0"]
        )
      ]
    end

    its([:version]) { is_expected.to eq(version_class.new("2.0.0")) }

    context "when the user is ignoring the lowest version" do
      let(:ignored_versions) { [">= 2.a, <= 2.0.0"] }
      its([:version]) { is_expected.to eq(version_class.new("2.0.3")) }
    end
  end

  describe "#versions" do
    subject(:versions) { finder.versions }

    it "includes the correct versions" do
      expect(versions.count).to eq(21)
      expect(versions.first).to eq(
        nuspec_url: "https://api.nuget.org/v3-flatcontainer/"\
                    "microsoft.extensions.dependencymodel/1.0.0-rc2-002702/"\
                    "microsoft.extensions.dependencymodel.nuspec",
        repo_url: "https://api.nuget.org/v3/index.json",
        source_url: nil,
        version: Dependabot::Nuget::Version.new("1.0.0.pre.rc2.pre.002702")
      )
    end
  end
end
