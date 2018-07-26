# frozen_string_literal: true

require "dependabot/file_fetchers/go/dep"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Go::Dep do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, url + "Gopkg.toml?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_gopkg_toml.json"),
        headers: { "content-type" => "application/json" }
      )
    stub_request(:get, url + "Gopkg.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_gopkg_lock.json"),
        headers: { "content-type" => "application/json" }
      )
    stub_request(:get, url + "?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_go_library.json"),
        headers: { "content-type" => "application/json" }
      )
  end

  it "fetches the Gopkg.toml and Gopkg.lock" do
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(Gopkg.toml Gopkg.lock))
  end

  context "without a Gopkg.lock" do
    before do
      stub_request(:get, url + "Gopkg.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "without a Gopkg.toml" do
    before do
      stub_request(:get, url + "Gopkg.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "for an application" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_go_app.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "main.go?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_gopkg_lock.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the main.go, too" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Gopkg.toml Gopkg.lock main.go))
    end
  end
end
