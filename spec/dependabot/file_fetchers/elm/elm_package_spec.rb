# frozen_string_literal: true

require "dependabot/file_fetchers/elm/elm_package"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Elm::ElmPackage do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:json_header) { { "content-type" => "application/json" } }
  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }
  before do
    stub_request(:get, url + "elm-package.json?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_elm_package.json"),
        headers: json_header
      )
  end

  it "fetches the elm-package.json" do
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(elm-package.json))
  end
end
