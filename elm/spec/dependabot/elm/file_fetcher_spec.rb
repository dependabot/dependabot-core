# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/elm/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Elm::FileFetcher do
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    stub_request(:get, url + "?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_elm_with_elm_package.json"),
        headers: json_header
      )
    stub_request(:get, url + "elm-package.json?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_elm_package.json"),
        headers: json_header
      )
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
  end

  it_behaves_like "a dependency file fetcher"

  context "with an elm.json" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_elm_with_elm_json.json"),
          headers: json_header
        )
      stub_request(:get, url + "elm.json?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_elm_package.json"),
          headers: json_header
        )
    end

    it "fetches the elm.json" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(elm.json))
    end
  end
end
