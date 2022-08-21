# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Swift::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:directory) { "/" }

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/LinkedList",
      directory: directory
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end

  let(:github_url) { "https://api.github.com/" }

  let(:url) { github_url + "repos/mona/LinkedList/contents/" }

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
  end

  context "with a Package.swift file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          headers: { "content-type" => "application/json" },
          body: fixture("github", "mona", "LinkedList", "repo.json")
        )

      %w(Package.swift Package.resolved).each do |filename|
        stub_request(:get, File.join(url, "#{filename}?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            headers: { "content-type" => "application/json" },
            body: fixture("github", "mona", "LinkedList", "#{filename}.json")
          )
      end
    end

    it "fetches the manifest and resolved files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Package.swift Package.resolved))
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/nonexistent" }

    before do
      %w(Package.swift Package.resolved).each do |filename|
        stub_request(:get, File.join(url, "nonexistent", "#{filename}?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: { "content-type" => "application/json" },
            body: fixture("github", "errors", "not_found.json")
          )
      end
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
