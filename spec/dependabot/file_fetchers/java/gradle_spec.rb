# frozen_string_literal: true

require "dependabot/file_fetchers/java/gradle"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Java::Gradle do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      host: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a basic buildfile" do
    before do
      stub_request(:get, File.join(url, "build.gradle?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_buildfile.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "settings.gradle?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the buildfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.gradle))
    end

    context "with a settings.gradle" do
      before do
        stub_request(:get, File.join(url, "settings.gradle?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_simple_settings.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url, "app/build.gradle?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_basic_buildfile.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the main buildfile and subproject buildfile" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(build.gradle app/build.gradle))
      end
    end
  end
end
