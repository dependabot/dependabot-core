# frozen_string_literal: true

require "dependabot/file_fetchers/php/composer"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Php::Composer do
  it_behaves_like "a dependency file fetcher"

  let(:source) { { host: "github", repo: "gocardless/bump" } }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, url + "composer.json?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "composer_json_content.json"),
        headers: { "content-type" => "application/json" }
      )
    stub_request(:get, url + "composer.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "composer_lock_content.json"),
        headers: { "content-type" => "application/json" }
      )
  end

  context "without a composer.lock" do
    before do
      stub_request(:get, url + "composer.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the composer.json" do
      expect(file_fetcher_instance.files.map(&:name)).to eq(["composer.json"])
    end
  end

  context "without a composer.json" do
    before do
      stub_request(:get, url + "composer.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
