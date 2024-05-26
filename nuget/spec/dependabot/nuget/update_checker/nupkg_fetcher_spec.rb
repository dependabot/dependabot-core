# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/nupkg_fetcher"
require "dependabot/nuget/update_checker/repository_finder"

RSpec.describe Dependabot::Nuget::NupkgFetcher do
  describe "#fetch_nupkg_url_from_repository" do
    let(:dependency) { Dependabot::Dependency.new(name: package_name, requirements: [], package_manager: "nuget") }
    let(:package_name) { "Newtonsoft.Json" }
    let(:package_version) { "13.0.1" }
    let(:credentials) { [] }
    let(:config_files) { [nuget_config] }
    let(:nuget_config) do
      Dependabot::DependencyFile.new(
        name: "NuGet.config",
        content: nuget_config_content
      )
    end
    let(:nuget_config_content) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <configuration>
          <packageSources>
            <clear />
            <add key="test-source" value="#{feed_url}" />
          </packageSources>
        </configuration>
      XML
    end
    let(:repository_finder) do
      Dependabot::Nuget::RepositoryFinder.new(dependency: dependency, credentials: credentials,
                                              config_files: config_files)
    end
    let(:repository_details) { repository_finder.dependency_urls.first }

    subject(:nupkg_url) do
      described_class.fetch_nupkg_url_from_repository(repository_details, package_name, package_version)
    end

    context "with a nuget feed url" do
      let(:feed_url) { "https://api.nuget.org/v3/index.json" }

      before do
        stub_request(:get, feed_url)
          .to_return(
            status: 200,
            body: fixture("nuget_responses", "index.json", "nuget.index.json")
          )
      end

      it { is_expected.to eq("https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.1/newtonsoft.json.13.0.1.nupkg") }
    end

    context "with an azure feed url" do
      let(:feed_url) { "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json" }

      before do
        stub_request(:get, feed_url)
          .to_return(
            status: 200,
            body: fixture("nuget_responses", "index.json", "dotnet-public.index.json")
          )
      end

      it { is_expected.to eq("https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/45bacae2-5efb-47c8-91e5-8ec20c22b4f8/nuget/v3/flat2/newtonsoft.json/13.0.1/newtonsoft.json.13.0.1.nupkg") }
    end

    context "with a github feed url" do
      let(:feed_url) { "https://nuget.pkg.github.com/some-namespace/index.json" }

      before do
        stub_request(:get, feed_url)
          .to_return(
            status: 200,
            body: fixture("nuget_responses", "index.json", "github.index.json")
          )
      end

      it { is_expected.to eq("https://nuget.pkg.github.com/some-namespace/download/newtonsoft.json/13.0.1/newtonsoft.json.13.0.1.nupkg") }
    end

    context "with a v2 feed url" do
      let(:feed_url) { "https://www.nuget.org/api/v2" }

      before do
        stub_request(:get, feed_url)
          .to_return(
            status: 200,
            body:
              +<<~XML
                <service xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom" xml:base="https://www.nuget.org/api/v2">
                  <workspace>
                    <collection href="Packages">
                      <atom:title type="text">Packages</atom:title>
                    </collection>
                  </workspace>
                </service>
              XML
          )
        stub_request(:get, "https://www.nuget.org/api/v2/Packages(Id='Newtonsoft.Json',Version='13.0.1')")
          .to_return(
            status: 200,
            body:
              <<~XML
                <entry xmlns:="http://www.w3.org/2005/Atom">
                  <content type="application/zip" src="https://www.nuget.org/api/v2/Download/Newtonsoft.Json/13.0.1" />
                  <!-- irrelevant elements omitted -->
                </entry>
              XML
          )
      end

      it { is_expected.to eq("https://www.nuget.org/api/v2/Download/Newtonsoft.Json/13.0.1") }
    end

    context "from a v3 feed that doesn't specify `PackageBaseAddress`" do
      let(:feed_url) { "https://nuget.example.com/v3-without-package-base/index.json" }

      before do
        # initial `index.json` response; only provides `SearchQueryService` and not `PackageBaseAddress`
        stub_request(:get, feed_url)
          .to_return(
            status: 200,
            body: {
              version: "3.0.0",
              resources: [
                {
                  "@id" => "https://nuget.example.com/query",
                  "@type" => "SearchQueryService"
                }
              ]
            }.to_json
          )
        # SearchQueryService
        stub_request(:get, "https://nuget.example.com/query?q=newtonsoft.json&prerelease=true&semVerLevel=2.0.0")
          .to_return(
            status: 200,
            body: {
              totalHits: 2,
              data: [
                # this is a false match
                {
                  registration: "not-used",
                  version: "42.42.42",
                  versions: [
                    {
                      version: "1.0.0",
                      "@id" => "not-used"
                    },
                    {
                      version: "42.42.42",
                      "@id" => "not-used"
                    }
                  ],
                  id: "Newtonsoft.Json.False.Match"
                },
                # this is the real one
                {
                  registration: "not-used",
                  version: "13.0.1",
                  versions: [
                    {
                      version: "12.0.1",
                      "@id" => "https://nuget.example.com/registration/newtonsoft.json/12.0.1.json"
                    },
                    {
                      version: "13.0.1",
                      "@id" => "https://nuget.example.com/registration/newtonsoft.json/13.0.1.json"
                    }
                  ],
                  id: "Newtonsoft.Json"
                }
              ]
            }.to_json
          )
        # registration content
        stub_request(:get, "https://nuget.example.com/registration/newtonsoft.json/13.0.1.json")
          .to_return(
            status: 200,
            body: {
              listed: true,
              packageContent: "https://nuget.example.com/nuget-local/Download/newtonsoft.json.13.0.1.nupkg",
              registration: "not-used",
              "@id" => "not-used"
            }.to_json
          )
      end

      it { is_expected.to eq("https://nuget.example.com/nuget-local/Download/newtonsoft.json.13.0.1.nupkg") }
    end
  end

  describe "#fetch_nupkg_buffer" do
    let(:package_id) { "Newtonsoft.Json" }
    let(:package_version) { "13.0.1" }
    let(:repository_details) { Dependabot::Nuget::RepositoryFinder.get_default_repository_details(package_id) }
    let(:dependency_urls) { [repository_details] }

    subject(:nupkg_buffer) do
      described_class.fetch_nupkg_buffer(dependency_urls, package_id, package_version)
    end

    before do
      stub_request(:get, "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.1/newtonsoft.json.13.0.1.nupkg")
        .to_return(
          status: 301,
          headers: {
            "Location" => "https://api.nuget.org/redirect-on-301"
          },
          body: "redirecting on 301"
        )
      stub_request(:get, "https://api.nuget.org/redirect-on-301")
        .to_return(
          status: 302,
          headers: {
            "Location" => "https://api.nuget.org/redirect-on-302"
          },
          body: "redirecting on 302"
        )
      stub_request(:get, "https://api.nuget.org/redirect-on-302")
        .to_return(
          status: 303,
          headers: {
            "Location" => "https://api.nuget.org/redirect-on-303"
          },
          body: "redirecting on 303"
        )
      stub_request(:get, "https://api.nuget.org/redirect-on-303")
        .to_return(
          status: 307,
          headers: {
            "Location" => "https://api.nuget.org/redirect-on-307"
          },
          body: "redirecting on 307"
        )
      stub_request(:get, "https://api.nuget.org/redirect-on-307")
        .to_return(
          status: 308,
          headers: {
            "Location" => "https://api.nuget.org/redirect-on-308"
          },
          body: "redirecting on 308"
        )
      stub_request(:get, "https://api.nuget.org/redirect-on-308")
        .to_return(
          status: 200,
          body: "the final contents"
        )
    end

    it "fetches the nupkg after multiple redirects" do
      expect(nupkg_buffer.to_s).to eq("the final contents")
    end
  end
end
