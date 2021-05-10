# frozen_string_literal: true

require "dependabot/source"
require "dependabot/config/file_fetcher"
require "spec_helper"

RSpec.describe Dependabot::Config::FileFetcher do
  let(:repo) { "gocardless/bump" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: "/",
      branch: "main",
      commit: "sha"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "region" => "us-east-1",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  describe "#config_file" do
    subject(:config_file) { file_fetcher_instance.config_file }
    let(:url) { "https://api.github.com/repos/#{repo}/contents/" }
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
      stub_request(:get, url + ".github/dependabot.yml?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    context "with config file" do
      before do
        stub_request(:get, url + ".github/dependabot.yaml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: fixture("github", "configfile_content.json"),
                    headers: { "content-type" => "application/json" })
      end

      it "fetches config file" do
        expect(config_file).to be_a(Dependabot::DependencyFile)
      end
    end

    context "without config file" do
      before do
        stub_request(:get, url + ".github/dependabot.yaml?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)
      end

      it "raises DependencyFileNotFound" do
        expect { config_file }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
