# frozen_string_literal: true

require "dependabot/file_fetchers/rust/cargo"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Rust::Cargo do
  it_behaves_like "a dependency file fetcher"

  let(:source) { { host: "github", repo: "gocardless/bump" } }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:json_header) { { "content-type" => "application/json" } }
  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }
  before do
    stub_request(:get, url + "Cargo.toml?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cargo_manifest.json"),
        headers: json_header
      )

    stub_request(:get, url + "Cargo.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cargo_lockfile.json"),
        headers: json_header
      )
  end

  context "with a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_with_lockfile.json"),
          headers: json_header
        )
    end

    it "fetches the Cargo.toml and Cargo.lock" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Cargo.lock Cargo.toml))
    end
  end

  context "without a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_cargo_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "fetches the Cargo.toml" do
      expect(file_fetcher_instance.files.map(&:name)).
        to eq(["Cargo.toml"])
    end
  end

  context "without a Cargo.toml" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_python.json"),
          headers: json_header
        )
      stub_request(:get, url + "Cargo.toml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
