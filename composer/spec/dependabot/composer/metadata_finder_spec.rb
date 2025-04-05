# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/composer/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Composer::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:packagist_response) do
    sanitized_name = dependency_name.downcase.gsub("/", "--")
    fixture("packagist_responses", "#{sanitized_name}.json")
  end
  let(:packagist_url) { "https://repo.packagist.org/p2/monolog/monolog.json" }
  let(:dependency_name) { "monolog/monolog" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements) do
    [{ file: "composer.json", requirement: "1.*", groups: [], source: nil }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      requirements: requirements,
      package_manager: "composer"
    )
  end

  before do
    packagist_url = "https://repo.packagist.org/p2/#{dependency_name.downcase}.json"
    stub_request(:get, packagist_url).to_return(status: 200, body: packagist_response)

    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when there is a github link in the packagist response" do
      it { is_expected.to eq("https://github.com/Seldaek/monolog") }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end

      context "when the package name includes capitals" do
        let(:dependency_name) { "monolog/MonoLog" }

        it "downcases the dependency name" do
          expect(finder.source_url).to eq("https://github.com/Seldaek/monolog")
          expect(WebMock)
            .to have_requested(
              :get,
              "https://repo.packagist.org/p2/monolog/monolog.json"
            )
        end
      end

      context "when the package listing is for a different package" do
        before do
          sanitized_name = "dependabot/dummy-pkg-a".downcase.gsub("/", "--")
          fixture = fixture("packagist_responses", "#{sanitized_name}.json")
          stub_request(:get, packagist_url)
            .to_return(status: 200, body: fixture)
        end

        it { is_expected.to be_nil }
      end
    end

    context "when there is a bitbucket link in the packagist response" do
      before do
        stub_request(:get, packagist_url)
          .to_return(status: 200, body: packagist_response.gsub!("github.com", "bitbucket.org"))
      end

      it { is_expected.to eq("https://bitbucket.org/Seldaek/monolog") }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end
    end

    context "when there is not a source link in the packagist response" do
      before do
        stub_request(:get, packagist_url)
          .to_return(status: 200, body: packagist_response.gsub!("github.com", "example.com"))
      end

      it { is_expected.to be_nil }

      it "caches the call to packagist" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, packagist_url).once
      end

      context "when there is a source URL on the dependency" do
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "1.*",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/Seldaek/monolog.git"
            }
          }]
        end

        it { is_expected.to eq("https://github.com/Seldaek/monolog") }

        it "doesn't hit packagist" do
          source_url
          expect(WebMock).not_to have_requested(:get, packagist_url)
        end
      end
    end

    context "when packagist returns an empty array" do
      let(:packagist_response) { '{"packages":[]}' }

      it { is_expected.to be_nil }
    end

    context "when the packagist link resolves to a redirect" do
      let(:redirect_url) { "https://repo.packagist.org/p2/monolog/Monolog.json" }

      before do
        stub_request(:get, packagist_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: packagist_response)
      end

      it { is_expected.to eq("https://github.com/Seldaek/monolog") }
    end

    context "when the packagist link 404s" do
      before { stub_request(:get, packagist_url).to_return(status: 404) }

      it { is_expected.to be_nil }
    end
  end
end
