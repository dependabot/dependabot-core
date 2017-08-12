# frozen_string_literal: true
require "dependabot/file_fetchers/ruby/gemspec"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Ruby::Gemspec do
  it_behaves_like "a dependency file fetcher"

  context "with a gemspec" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(
        repo: "gocardless/business",
        github_client: github_client
      )
    end

    let(:url) { "https://api.github.com/repos/gocardless/business/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "business.gemspec?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the gemspec file" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("business.gemspec")
    end
  end

  context "with no gemspec" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(
        repo: "gocardless/business",
        github_client: github_client
      )
    end

    let(:url) { "https://api.github.com/repos/gocardless/business/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
