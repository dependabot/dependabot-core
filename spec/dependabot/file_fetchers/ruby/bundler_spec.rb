# frozen_string_literal: true
require "dependabot/file_fetchers/ruby/bundler"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler do
  it_behaves_like "a dependency file fetcher"

  context "with path dependency" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "plugins/bump-core/bump-core.gemspec?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches gemspec from path dependency" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("plugins/bump-core/bump-core.gemspec")
    end
  end
end
