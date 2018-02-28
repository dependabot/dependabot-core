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
      requirements: requirements,
      package_manager: "composer"
    )
  end
  let(:requirements) do
    [{ file: "composer.json", requirement: "1.*", groups: [], source: nil }]
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:dependency_name) { "monolog/monolog" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:packagist_url) { "https://packagist.org/p/monolog/monolog.json" }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
    end

    context "when there is a github link in the packagist response" do
      let(:packagist_response) { fixture("php", "packagist_response.json") }

      it { is_expected.to eq("https://github.com/Seldaek/monolog") }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end

      context "when the package name includes capitals" do
        let(:dependency_name) { "monolog/MonoLog" }

        it "downcases the dependency name" do
          expect(finder.source_url).to eq("https://github.com/Seldaek/monolog")
          expect(WebMock).
            to have_requested(
              :get,
              "https://packagist.org/p/monolog/monolog.json"
            )
        end
      end

      context "when the package listing is for a different" do
        let(:dependency_name) { "monolog/something" }
        let(:packagist_url) { "https://packagist.org/p/monolog/something.json" }

        it { is_expected.to be_nil }
      end
    end

    context "when there is a bitbucket link in the packagist response" do
      let(:packagist_response) do
        fixture("php", "packagist_response_bitbucket.json")
      end

      it { is_expected.to eq("https://bitbucket.org/Seldaek/monolog") }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end
    end

    context "when there is not a source link in the packagist response" do
      let(:packagist_response) do
        fixture("php", "packagist_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end

      context "but there is a source URL on the dependency" do
        let(:requirements) do
          [
            {
              file: "composer.json",
              requirement: "1.*",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/Seldaek/monolog.git"
              }
            }
          ]
        end

        it { is_expected.to eq("https://github.com/Seldaek/monolog") }

        it "doesn't hit packagist" do
          source_url
          expect(WebMock).to_not have_requested(:get, packagist_url)
        end
      end
    end

    context "when packagist returns an empty array" do
      let(:packagist_response) { '{"packages":[]}' }

      it { is_expected.to be_nil }
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

      it { is_expected.to eq("https://github.com/Seldaek/monolog") }
    end

    context "when the packagist link 404s" do
      let(:packagist_response) { fixture("php", "packagist_response.json") }

      before { stub_request(:get, packagist_url).to_return(status: 404) }
      it { is_expected.to be_nil }
    end
  end
end
