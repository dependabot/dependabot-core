# frozen_string_literal: true

require "spec_helper"
require "dependabot/puppet/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Puppet::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:repo) { "jpogran/control-repo" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: directory
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/#{repo}/contents/" }
  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a Puppetfile" do
    before do
      stub_request(:get, File.join(url, "Puppetfile?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_puppetfile.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the Puppetfile" do
      expect(file_fetcher_instance.files.map(&:name)).to include("Puppetfile")
    end
  end

  context "without a Puppetfile" do
    before do
      stub_request(:get, File.join(url, "Puppetfile?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404,
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
