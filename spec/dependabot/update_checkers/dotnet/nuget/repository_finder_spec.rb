# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/dotnet/nuget/repository_finder"

RSpec.describe Dependabot::UpdateCheckers::Dotnet::Nuget::RepositoryFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      config_file: config_file
    )
  end
  let(:config_file) { nil }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Microsoft.Extensions.DependencyModel",
      version: "1.1.1",
      requirements: [{
        requirement: "1.1.1",
        file: "my.csproj",
        groups: [],
        source: nil
      }],
      package_manager: "nuget"
    )
  end

  describe "dependency_urls" do
    subject(:dependency_urls) { finder.dependency_urls }

    it "gets the right URL without making any requests" do
      expect(dependency_urls).to eq(
        [
          {
            repository_url: "https://api.nuget.org/v3/index.json",
            versions_url:   "https://api.nuget.org/v3-flatcontainer/"\
                            "microsoft.extensions.dependencymodel/index.json"
          }
        ]
      )
    end

    context "with a URL passed as a credential" do
      let(:custom_repo_url) do
        "https://www.myget.org/F/exceptionless/api/v3/index.json"
      end
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          {
            "type" => "nuget_repository",
            "url" => custom_repo_url,
            "token" => "my:passw0rd"
          }
        ]
      end

      before do
        stub_request(:get, custom_repo_url).
          with(basic_auth: %w(my passw0rd)).
          to_return(
            status: 200,
            body: fixture("dotnet", "nuget_responses", "myget_base.json")
          )
      end

      it "gets the right URL" do
        expect(dependency_urls).to eq(
          [
            {
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/"\
                              "index.json",
              versions_url:   "https://www.myget.org/F/exceptionless/api/v3/"\
                              "flatcontainer/microsoft.extensions."\
                              "dependencymodel/index.json"
            }
          ]
        )
      end

      context "that 404s" do
        before { stub_request(:get, custom_repo_url).to_return(status: 404) }

        # TODO: Might want to raise here instead?
        it { is_expected.to eq([]) }
      end
    end

    context "with a URL included in the nuget.config" do
      let(:config_file) do
        Dependabot::DependencyFile.new(
          name: "NuGet.Config",
          content: fixture("dotnet", "configs", "nuget.config")
        )
      end

      before do
        repo_url = "https://www.myget.org/F/exceptionless/api/v3/index.json"
        stub_request(:get, repo_url).to_return(
          status: 200,
          body: fixture("dotnet", "nuget_responses", "myget_base.json")
        )
      end

      it "gets the right URLs" do
        expect(dependency_urls).to match_array(
          [
            {
              repository_url: "https://api.nuget.org/v3/index.json",
              versions_url:   "https://api.nuget.org/v3-flatcontainer/"\
                              "microsoft.extensions.dependencymodel/index.json"
            },
            {
              repository_url: "https://www.myget.org/F/exceptionless/api/v3/"\
                              "index.json",
              versions_url:   "https://www.myget.org/F/exceptionless/api/v3/"\
                              "flatcontainer/microsoft.extensions."\
                              "dependencymodel/index.json"
            }
          ]
        )
      end
    end
  end
end
