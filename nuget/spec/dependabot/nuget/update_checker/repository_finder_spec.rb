# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/repository_finder"

RSpec.describe Dependabot::Nuget::RepositoryFinder do
  describe "#escape_source_name_to_element_name" do
    subject(:escaped) do
      described_class.escape_source_name_to_element_name(source_name)
    end

    context "when the source name needs no escaping" do
      let(:source_name) { "some_source-name.1" }

      it { is_expected.to eq("some_source-name.1") }
    end

    context "when the source name has a space" do
      let(:source_name) { "source name" }

      it { is_expected.to eq("source_x0020_name") }
    end

    context "when the source name has other characters that need to be escaped" do
      let(:source_name) { "source@local" }

      it { is_expected.to eq("source_x0040_local") }
    end
  end

  describe "#dependency_urls" do
    subject(:dependency_urls) do
      described_class.new(
        dependency: Dependabot::Dependency.new(
          name: "Some.Package",
          version: "1.0.0",
          requirements: [],
          package_manager: "nuget"
        ),
        credentials: credentials,
        config_files: config_files
      ).send(:dependency_urls)
    end

    context "when package source name contains non-identifier characters" do
      let(:credentials) { [] }
      let(:config_files) do
        [
          Dependabot::DependencyFile.new(
            name: "NuGet.Config",
            content:
              <<~XML
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <!-- the `@` symbol in the name can cause issues when searching through this file -->
                    <add key="nuget-mirror@local" value="https://nuget.example.com/v3/index.json" />
                  </packageSources>
                </configuration>
              XML
          )
        ]
      end

      before do
        stub_request(:get, "https://nuget.example.com/v3/index.json")
          .to_return(
            status: 200,
            body: {
              version: "3.0.0",
              resources: [
                {
                  "@id": "https://nuget.example.com/v3/base",
                  "@type": "PackageBaseAddress/3.0.0"
                },
                {
                  "@id": "https://nuget.example.com/v3/registrations",
                  "@type": "RegistrationsBaseUrl"
                },
                {
                  "@id": "https://nuget.example.com/v3/search",
                  "@type": "SearchQueryService/3.5.0"
                }
              ]
            }.to_json
          )
      end

      it "returns the urls" do
        expect(dependency_urls).to eq(
          [{
            auth_header: {},
            base_url: "https://nuget.example.com/v3/base",
            registration_url: "https://nuget.example.com/v3/registrations/some.package/index.json",
            repository_type: "v3",
            repository_url: "https://nuget.example.com/v3/index.json",
            search_url: "https://nuget.example.com/v3/search?q=some.package&prerelease=true&semVerLevel=2.0.0",
            versions_url: "https://nuget.example.com/v3/base/some.package/index.json"
          }]
        )
      end
    end
  end
end
