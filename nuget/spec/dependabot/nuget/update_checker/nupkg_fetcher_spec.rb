# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/nupkg_fetcher"

RSpec.describe Dependabot::Nuget::NupkgFetcher do
  describe "#try_match_azure_url" do
    context "when checking with a azure feed url" do
      let(:url) { "https://pkgs.dev.azure.com/dependabot/dependabot-test/_packaging/dependabot-feed/nuget/v3/index.json" }
      subject(:match) { described_class.try_match_azure_url(url) }

      it { is_expected.to be_truthy }
      it { expect(match[:organization]).to eq("dependabot") }
      it { expect(match[:project]).to eq("dependabot-test") }
      it { expect(match[:feedId]).to eq("dependabot-feed") }
    end

    context "when checking with a azure feed url (no project)" do
      let(:url) { "https://pkgs.dev.azure.com/dependabot/_packaging/dependabot-feed/nuget/v3/index.json" }
      subject(:match) { described_class.try_match_azure_url(url) }

      it { is_expected.to be_truthy }
      it { expect(match[:organization]).to eq("dependabot") }
      it { expect(match[:project]).to be_empty }
      it { expect(match[:feedId]).to eq("dependabot-feed") }
    end

    context "when checking with a visual studio feed url" do
      let(:url) { "https://dynamicscrm.pkgs.visualstudio.com/_packaging/CRM.Engineering/nuget/v3/index.json" }
      subject(:match) { described_class.try_match_azure_url(url) }

      it { is_expected.to be_truthy }
      it { expect(match[:organization]).to eq("dynamicscrm") }
      it { expect(match[:project]).to be_empty }
      it { expect(match[:feedId]).to eq("CRM.Engineering") }
    end

    context "when checking with the nuget.org feed url" do
      let(:url) { "https://api.nuget.org/v3/index.json" }
      subject(:match) { described_class.try_match_azure_url(url) }

      it { is_expected.to be_falsey }
    end
  end

  describe "#get_azure_package_url" do
    context "when checking with a azure feed url" do
      let(:url) { "https://pkgs.dev.azure.com/dependabot/dependabot-test/_packaging/dependabot-feed/nuget/v3/index.json" }
      let(:match) { described_class.try_match_azure_url(url) }
      let(:package_name) { "Newtonsoft.Json" }
      let(:package_version) { "13.0.1" }
      subject(:package_url) { described_class.get_azure_package_url(match, package_name, package_version) }

      it { is_expected.to eq("https://pkgs.dev.azure.com/dependabot/dependabot-test/_apis/packaging/feeds/dependabot-feed/nuget/packages/Newtonsoft.Json/versions/13.0.1/content?sourceProtocolVersion=nuget&api-version=7.0-preview") }
    end

    context "when checking with a azure feed url (no project)" do
      let(:url) { "https://pkgs.dev.azure.com/dependabot/_packaging/dependabot-feed/nuget/v3/index.json" }
      let(:match) { described_class.try_match_azure_url(url) }
      let(:package_name) { "Newtonsoft.Json" }
      let(:package_version) { "13.0.1" }
      subject(:package_url) { described_class.get_azure_package_url(match, package_name, package_version) }

      it { is_expected.to eq("https://pkgs.dev.azure.com/dependabot/_apis/packaging/feeds/dependabot-feed/nuget/packages/Newtonsoft.Json/versions/13.0.1/content?sourceProtocolVersion=nuget&api-version=7.0-preview") }
    end

    context "when checking with a visual studio feed url" do
      let(:url) { "https://dynamicscrm.pkgs.visualstudio.com/_packaging/CRM.Engineering/nuget/v3/index.json" }
      let(:match) { described_class.try_match_azure_url(url) }
      let(:package_name) { "Newtonsoft.Json" }
      let(:package_version) { "13.0.1" }
      subject(:package_url) { described_class.get_azure_package_url(match, package_name, package_version) }

      it { is_expected.to eq("https://pkgs.dev.azure.com/dynamicscrm/_apis/packaging/feeds/CRM.Engineering/nuget/packages/Newtonsoft.Json/versions/13.0.1/content?sourceProtocolVersion=nuget&api-version=7.0-preview") }
    end
  end

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
      Dependabot::Nuget::UpdateChecker::RepositoryFinder.new(dependency: dependency, credentials: credentials,
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

      it { is_expected.to eq("https://pkgs.dev.azure.com/dnceng/public/_apis/packaging/feeds/dotnet-public/nuget/packages/Newtonsoft.Json/versions/13.0.1/content?sourceProtocolVersion=nuget&api-version=7.0-preview") }
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
  end
end
