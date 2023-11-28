# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/nuspec_fetcher"

RSpec.describe Dependabot::Nuget::UpdateChecker::NupkgFetcher do
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
end
