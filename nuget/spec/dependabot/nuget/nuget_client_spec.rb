# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/nuget_client"

RSpec.describe Dependabot::Nuget::NugetClient do
  describe "#get_package_versions" do
    let(:dependency_name) { "Some.Dependency" }

    subject(:package_versions) do
      Dependabot::Nuget::NugetClient.get_package_versions(dependency_name, repository_details)
    end

    context "package versions from local" do
      let(:repository_details) do
        nuget_dir = File.join(File.dirname(__FILE__), "..", "..", "fixtures", "nuget_responses", "local_repo")
        base_url = URI(nuget_dir).normalize.to_s

        {
          base_url: base_url,
          repository_type: "local"
        }
      end

      it "expects to crawl the directory" do
        expect(package_versions).to eq(Set["1.0.0", "1.1.0"])
      end
    end

    context "package versions _might_ have the `listed` flag" do
      before do
        stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/#{dependency_name.downcase}/index.json")
          .to_return(
            status: 200,
            body: {
              items: [
                items: [
                  {
                    catalogEntry: {
                      listed: true, # nuget.org provides this flag and it should be honored
                      version: "0.1.0"
                    }
                  },
                  {
                    catalogEntry: {
                      listed: false, # if this is ever false, the package should not be included
                      version: "0.1.1"
                    }
                  },
                  {
                    catalogEntry: {
                      # e.g., github doesn't have the `listed` flag, but should still be returned
                      version: "0.1.2"
                    }
                  }
                ]
              ]
            }.to_json
          )
      end

      let(:repository_details) do
        {
          base_url: "https://api.nuget.org/v3-flatcontainer/",
          registration_url: "https://api.nuget.org/v3/registration5-gz-semver2/#{dependency_name.downcase}/index.json",
          repository_url: "https://api.nuget.org/v3/index.json",
          versions_url: "https://api.nuget.org/v3-flatcontainer/" \
                        "#{dependency_name.downcase}/index.json",
          search_url: "https://azuresearch-usnc.nuget.org/query" \
                      "?q=#{dependency_name.downcase}&prerelease=true&semVerLevel=2.0.0",
          auth_header: {},
          repository_type: "v3"
        }
      end

      it "returns the correct version information" do
        expect(package_versions).to eq(Set["0.1.0", "0.1.2"])
      end
    end

    context "versions can be retrieved from v2 apis" do
      before do
        stub_request(:get, "https://www.nuget.org/api/v2/FindPackagesById()?id=%27Some.Dependency%27")
          .to_return(
            status: 200,
            body:
              <<~XML
                <?xml version="1.0" encoding="utf-8"?>
                <feed xml:base="https://www.nuget.org/api/v2" xmlns="http://www.w3.org/2005/Atom"
                      xmlns:d="htps://schemas.microsoft.com/ado/2007/08/dataservices"
                      xmlns:m="htps://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
                  <!-- irrelevant elements omitted -->
                  <entry>
                    <title type="text">Some.Dependency</title>
                    <m:properties>
                      <!-- n.b., NuGet normally returns a `[d:Id]Some.Dependency[/d:Id]` element here, but not all feeds
                      report this, so it's intentionally being omitted -->
                      <d:Version>1.0.0.0</d:Version>
                      <!-- other irrelevant elements omitted -->
                    </m:properties>
                  </entry>
                  <entry>
                    <title type="text">Some.Dependency</title>
                    <m:properties>
                      <d:Version>1.1.0.0</d:Version>
                      <!-- other irrelevant elements omitted -->
                    </m:properties>
                  </entry>
                  <entry>
                    <title type="text">Some.Dependency.But.The.Wrong.One</title>
                    <m:properties>
                      <d:Version>1.2.0.0</d:Version>
                      <!-- other irrelevant elements omitted -->
                    </m:properties>
                  </entry>
                <feed>
              XML
          )
      end

      let(:repository_details) do
        {
          base_url: "https://www.nuget.org/api/v2",
          repository_url: "https://www.nuget.org/api/v2",
          versions_url: "https://www.nuget.org/api/v2/FindPackagesById()?id='#{dependency_name}'",
          auth_header: {},
          repository_type: "v2"
        }
      end

      it "returns the correct version information" do
        expect(package_versions).to eq(Set["1.0.0.0", "1.1.0.0"])
      end
    end
  end
end
