# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/helm/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Helm::FileFetcher do
  let(:credentials) do
    [{
       "type" => "git_source",
       "host" => "github.com",
       "username" => "x-access-token",
       "password" => "token"
     }]
  end
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
  end

  context "with no Helm file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_no_helm_repo.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises the expected error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with helm" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_helm_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Charts.yaml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: helmfile_fixture,
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "values.yaml?ref=sha"))
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: helmfile_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:helmfile_fixture) do
      fixture("github", "contents_helm.json")
    end

    it "fetches the Charts.yml file" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(Charts.yaml values.yaml))
    end

    context "with invalid encoding" do
      let(:helmfile_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
