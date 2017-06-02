# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/php/composer"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Php::Composer do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      package_manager: "composer"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:dependency_name) { "monolog/monolog" }

  describe "#github_repo" do
    subject(:github_repo) { finder.github_repo }
    let(:packagist_url) { "https://packagist.org/p/monolog/monolog.json" }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
    end

    context "when there is a github link in the packagist response" do
      let(:packagist_response) { fixture("php", "packagist_response.json") }

      it { is_expected.to eq("Seldaek/monolog") }

      it "caches the call to packagist" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end
    end

    context "when there is not a github link in the packagist response" do
      let(:packagist_response) do
        fixture("php", "packagist_response_no_github.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to packagist" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end
    end

    context "when the packagist link resolves to a redirect" do
      let(:redirect_url) { "https://packagist.org/p/monolog/Monolog.json" }
      let(:packagist_response) { fixture("php", "packagist_response.json") }

      before do
        stub_request(:get, packagist_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: packagist_response)
      end

      it { is_expected.to eq("Seldaek/monolog") }
    end
  end
end
