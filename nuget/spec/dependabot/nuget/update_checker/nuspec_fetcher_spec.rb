# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/update_checker/nuspec_fetcher"

RSpec.describe Dependabot::Nuget::NuspecFetcher do
  describe "#feed_supports_nuspec_download?" do
    context "when checking with a azure feed url" do
      subject(:result) { described_class.feed_supports_nuspec_download?(url) }

      let(:url) { "https://pkgs.dev.azure.com/dependabot/dependabot-test/_packaging/dependabot-feed/nuget/v3/index.json" }

      it { is_expected.to be_truthy }
    end

    context "when checking with a azure feed url (no project)" do
      subject(:result) { described_class.feed_supports_nuspec_download?(url) }

      let(:url) { "https://pkgs.dev.azure.com/dependabot/_packaging/dependabot-feed/nuget/v3/index.json" }

      it { is_expected.to be_truthy }
    end

    context "when checking with a visual studio feed url" do
      subject(:result) { described_class.feed_supports_nuspec_download?(url) }

      let(:url) { "https://dynamicscrm.pkgs.visualstudio.com/_packaging/CRM.Engineering/nuget/v3/index.json" }

      it { is_expected.to be_truthy }
    end

    context "when checking with the nuget.org feed url" do
      subject(:result) { described_class.feed_supports_nuspec_download?(url) }

      let(:url) { "https://api.nuget.org/v3/index.json" }

      it { is_expected.to be_truthy }
    end

    context "when checking with github feed url" do
      subject(:result) { described_class.feed_supports_nuspec_download?(url) }

      let(:url) { "https://nuget.pkg.github.com/some_namespace/index.json" }

      it { is_expected.to be_falsy }
    end
  end

  describe "remove_invalid_characters" do
    context "when a utf-16 bom is present" do
      subject(:result) { described_class.remove_invalid_characters(response_body) }

      let(:response_body) { "\xFE\xFF<xml></xml>" }

      it { is_expected.to eq("<xml></xml>") }
    end
  end
end
