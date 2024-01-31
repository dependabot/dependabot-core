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
  end
end
