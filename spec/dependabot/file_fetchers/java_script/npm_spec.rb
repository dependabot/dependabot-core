# frozen_string_literal: true

require "dependabot/file_fetchers/java_script/npm"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::JavaScript::Npm do
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

    stub_request(:get, url + "package.json?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "package_json_content.json"),
        headers: { "content-type" => "application/json" }
      )

    stub_request(:get, url + "package-lock.json?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "package_lock_content.json"),
        headers: { "content-type" => "application/json" }
      )

    stub_request(:get, url + ".npmrc?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(status: 404)
  end

  context "with a .npmrc file" do
    before do
      stub_request(:get, url + ".npmrc?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "npmrc_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .npmrc" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).to include(".npmrc")
    end
  end

  context "without a package-lock.json file" do
    before do
      stub_request(:get, url + "package-lock.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the package.json" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).to eq(["package.json"])
    end
  end

  context "with a path dependency" do
    before do
      stub_request(:get, url + "package.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "package_json_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "with a bad package.json" do
      before do
        stub_request(:get, url + "package.json?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("package.json")
          end
      end
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, url + "deps/etag/package.json?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches package.json from path dependency" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("deps/etag/package.json")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + "deps/etag/package.json?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)
      end

      it "raises a PathDependenciesNotReachable error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: " \
            "etag"
          )
      end
    end
  end
end
